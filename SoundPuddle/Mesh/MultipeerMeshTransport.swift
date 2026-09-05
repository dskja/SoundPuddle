import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class MultipeerMeshTransport: NSObject, MeshTransporting {
    private let serviceType = SessionAdvertisement.serviceType
    private let myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var eventContinuation: AsyncStream<MeshEvent>.Continuation?
    private(set) lazy var events: AsyncStream<MeshEvent> = AsyncStream { continuation in
        self.eventContinuation = continuation
    }

    private var pendingPeers: [String: MCPeerID] = [:]
    private var autoAcceptInvitations = true
    private var hostingCapacity = SessionAdvertisement.maxJoiners
    private var isHosting = false

    private(set) var connectedPeers: [MeshPeer] = []

    override init() {
        let stored = UserDefaults.standard.string(forKey: "displayName")
        let name = String((stored ?? UIDevice.current.name).prefix(20))
        myPeerID = MCPeerID(displayName: name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func startHosting(advertisement: SessionAdvertisement) {
        isHosting = true
        hostingCapacity = advertisement.capacity
        stopBrowsing()
        advertiser?.stopAdvertisingPeer()
        let adv = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: advertisement.discoveryInfo,
            serviceType: serviceType
        )
        adv.delegate = self
        advertiser = adv
        adv.startAdvertisingPeer()
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isHosting = false
    }

    func startBrowsing() {
        isHosting = false
        stopHosting()
        browser?.stopBrowsingForPeers()
        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        b.delegate = self
        browser = b
        b.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func invite(_ peer: MeshPeer) {
        guard let browser else {
            emit(.error(.mesh(String(localized: "error.browserInactive"))))
            return
        }
        guard let target = pendingPeers[peer.displayName] else {
            emit(.error(.mesh(String(localized: "error.peerMissing"))))
            return
        }
        browser.invitePeer(target, to: session, withContext: nil, timeout: 12)
        emit(.peerStateChanged(MeshPeer(id: peer.id, displayName: peer.displayName, state: .connecting)))
    }

    func acceptInvitations(_ accept: Bool) {
        autoAcceptInvitations = accept
    }

    func sendControl(_ message: ControlMessage, to peers: [MeshPeer]?) {
        do {
            let data = try ControlCodec.encode(message)
            let targets = resolve(peers)
            guard !targets.isEmpty else { return }
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            emit(.error(.mesh(error.localizedDescription)))
        }
    }

    func sendAudio(_ packet: Data, to peers: [MeshPeer]?) {
        let targets = resolve(peers)
        guard !targets.isEmpty else { return }
        try? session.send(packet, toPeers: targets, with: .unreliable)
    }

    func disconnect() {
        stopHosting()
        stopBrowsing()
        session.disconnect()
        session.delegate = nil
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        connectedPeers = []
        pendingPeers.removeAll()
    }

    private func resolve(_ peers: [MeshPeer]?) -> [MCPeerID] {
        guard let peers else { return session.connectedPeers }
        let names = Set(peers.map(\ .displayName))
        return session.connectedPeers.filter { names.contains($0.displayName) }
    }

    private func emit(_ event: MeshEvent) {
        eventContinuation?.yield(event)
    }

    private func syncConnectedPeers() {
        connectedPeers = session.connectedPeers.map {
            MeshPeer(id: $0.displayName, displayName: $0.displayName, state: .connected)
        }
    }
}

extension MultipeerMeshTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let mapped: MeshPeer.PeerConnectionState
            switch state {
            case .connected: mapped = .connected
            case .connecting: mapped = .connecting
            case .notConnected: mapped = .notConnected
            @unknown default: mapped = .notConnected
            }
            let peer = MeshPeer(id: peerID.displayName, displayName: peerID.displayName, state: mapped)
            self.syncConnectedPeers()
            self.emit(.peerStateChanged(peer))
            switch state {
            case .connected:
                self.emit(.connected(peer))
            case .notConnected:
                self.emit(.disconnected(peer))
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            if PacketHeader.decode(from: data) != nil {
                self.emit(.audio(data, from: peerID.displayName))
                return
            }
            if let message = try? ControlCodec.decode(data), let message {
                self.emit(.control(message, from: peerID.displayName))
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerMeshTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            let accept = self.isHosting
                && self.autoAcceptInvitations
                && self.session.connectedPeers.count < self.hostingCapacity
            if !accept && self.isHosting {
                self.emit(.error(.sessionFull))
            }
            invitationHandler(accept, accept ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.emit(.error(.mesh(error.localizedDescription)))
        }
    }
}

extension MultipeerMeshTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.pendingPeers[peerID.displayName] = peerID
            let ad = SessionAdvertisement.from(discoveryInfo: info)
            let peer = MeshPeer(id: peerID.displayName, displayName: peerID.displayName, state: .discovered)
            self.emit(.peerDiscovered(peer, ad))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.pendingPeers.removeValue(forKey: peerID.displayName)
            self.emit(.peerLost(peerID.displayName))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.emit(.error(.mesh(error.localizedDescription)))
        }
    }
}
