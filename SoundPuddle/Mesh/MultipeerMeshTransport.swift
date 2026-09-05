import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class MultipeerMeshTransport: NSObject, MeshTransporting {
    private let serviceType = SessionAdvertisement.serviceType
    private var myPeerID: MCPeerID
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
    private var advertiseRetry = 0
    private var browseRetry = 0
    private var isBrowsing = false
    private var lastDiscoveryInfo: [String: String] = [:]

    private(set) var connectedPeers: [MeshPeer] = []

    private static var encryptionPreference: MCEncryptionPreference {
        switch LiveContainerRuntime.preferredEncryption {
        case .required: return .required
        case .optional: return .optional
        case .none: return .none
        }
    }

    /// Bonjour/Multipeer rejects odd Unicode peer names in some LiveContainer sandboxes.
    private static func sanitizedDisplayName() -> String {
        let stored = UserDefaults.standard.string(forKey: "displayName")
        let raw = stored ?? UIDevice.current.name
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(cleaned.prefix(20))
        return clipped.isEmpty ? "iPhone" : clipped
    }

    private static func compactDiscoveryInfo(_ info: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in info {
            out[String(key.prefix(20))] = String(value.prefix(60))
        }
        return out
    }

    private static func friendlyBonjourMessage(from error: Error) -> String {
        let ns = error as NSError
        let isNetService = ns.domain.contains("NetService") || ns.domain.contains("DNS")
        let is72008 = ns.code == -72008 || ns.localizedDescription.contains("-72008")
        if isNetService || is72008 {
            if LiveContainerRuntime.isActive {
                return String(localized: "error.bonjour.livecontainer")
            }
            return String(localized: "error.bonjour.localNetwork")
        }
        return error.localizedDescription
    }

    override init() {
        let name = Self.sanitizedDisplayName()
        myPeerID = MCPeerID(displayName: name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: Self.encryptionPreference)
        super.init()
        session.delegate = self
    }

    func startHosting(advertisement: SessionAdvertisement) {
        isHosting = true
        hostingCapacity = advertisement.capacity
        advertiseRetry = 0
        lastDiscoveryInfo = Self.compactDiscoveryInfo(advertisement.discoveryInfo)
        stopBrowsing()
        beginAdvertising()
    }

    private func beginAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        let adv = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: lastDiscoveryInfo,
            serviceType: serviceType
        )
        adv.delegate = self
        advertiser = adv
        adv.startAdvertisingPeer()
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        isHosting = false
        advertiseRetry = 0
    }

    func startBrowsing() {
        isHosting = false
        isBrowsing = true
        browseRetry = 0
        stopHosting()
        beginBrowsing()
    }

    private func beginBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        b.delegate = self
        browser = b
        b.startBrowsingForPeers()
    }

    func stopBrowsing() {
        isBrowsing = false
        browseRetry = 0
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
    }

    func invite(_ peer: MeshPeer) {
        guard let browser else {
            emit(.error(.mesh(String(localized: "error.browserInactive"))))
            return
        }
        guard let target = pendingPeers[peer.id] ?? pendingPeers[peer.displayName] else {
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
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: Self.encryptionPreference)
        session.delegate = self
        connectedPeers = []
        pendingPeers.removeAll()
    }

    private func resolve(_ peers: [MeshPeer]?) -> [MCPeerID] {
        guard let peers else { return session.connectedPeers }
        let ids = Set(peers.map(\.id))
        let names = Set(peers.map(\.displayName))
        return session.connectedPeers.filter { ids.contains(String($0.hash)) || names.contains($0.displayName) }
    }

    private func emit(_ event: MeshEvent) {
        eventContinuation?.yield(event)
    }

    private func syncConnectedPeers() {
        connectedPeers = session.connectedPeers.map {
            MeshPeer(id: String($0.hash), displayName: $0.displayName, state: .connected)
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
            let peer = MeshPeer(id: String(peerID.hash), displayName: peerID.displayName, state: mapped)
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
            do {
                if let message = try ControlCodec.decode(data) {
                    self.emit(.control(message, from: peerID.displayName))
                }
            } catch {
                self.emit(.error(.mesh(error.localizedDescription)))
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
            // Late Local Network permission / LiveContainer Bonjour flakiness — retry a few times.
            if self.advertiseRetry < 3 {
                self.advertiseRetry += 1
                try? await Task.sleep(nanoseconds: UInt64(self.advertiseRetry) * 700_000_000)
                guard self.isHosting else { return }
                self.beginAdvertising()
                return
            }
            self.emit(.error(.mesh(Self.friendlyBonjourMessage(from: error))))
        }
    }
}

extension MultipeerMeshTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.pendingPeers[String(peerID.hash)] = peerID
            self.pendingPeers[peerID.displayName] = peerID
            let ad = SessionAdvertisement.from(discoveryInfo: info)
            let peer = MeshPeer(id: String(peerID.hash), displayName: peerID.displayName, state: .discovered)
            self.emit(.peerDiscovered(peer, ad))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.pendingPeers.removeValue(forKey: String(peerID.hash))
            self.pendingPeers.removeValue(forKey: peerID.displayName)
            self.emit(.peerLost(peerID.displayName))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            // Same LiveContainer / Local Network late-grant path as advertising.
            if self.browseRetry < 3 {
                self.browseRetry += 1
                try? await Task.sleep(nanoseconds: UInt64(self.browseRetry) * 700_000_000)
                guard self.isBrowsing else { return }
                self.beginBrowsing()
                return
            }
            self.emit(.error(.mesh(Self.friendlyBonjourMessage(from: error))))
        }
    }
}
