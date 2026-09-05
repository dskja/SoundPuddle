import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case home
        case hostSetup
        case hostLive
        case joinBrowse
        case joinConnecting
        case joinCalibrate
        case joinLive
    }

    enum HostSource: Equatable {
        case microphone
        case file(URL)
    }

    // MARK: View-facing state (Features contract)
    var route: Route = .home
    var sessionTitle = ""
    var sessionMode: SessionMode = .schwarm
    var hostSource: HostSource = .microphone
    var discovered: [(peer: MeshPeer, ad: SessionAdvertisement)] = []
    var peers: [MeshPeer] = []
    var audioLevel: Float = 0
    var linkQuality: LinkQuality = .good
    var lastError: String?
    var isStreaming = false
    var showPermissionHint = false
    var displayName: String = UserDefaults.standard.string(forKey: "displayName") ?? UIDevice.current.name
    var underrunCountPublic: Int { underrunCount }
    var isLiveContainer: Bool { LiveContainerRuntime.isActive }
    var importedFileLabel: String? {
        if case .file(let url) = hostSource { return url.lastPathComponent }
        return nil
    }

    var isStreamPaused = false
    var hostMonitorMuted = true
    var joinVolume: Float = 1
    var isMuted = false
    var rosterNames: [String] = []
    var lastRTT: Int?
    var sessionStartedAt: Date?

    var sessionElapsedLabel: String {
        guard let start = sessionStartedAt else { return "00:00" }
        let secs = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    var rttLabel: String {
        lastRTT.map { "\($0) ms" } ?? "—"
    }

    var diagnosticsLine: String {
        let lc = isLiveContainer ? "LC" : "native"
        let pause = isStreamPaused ? " · paused" : ""
        return "\(lc) · \(myRole.rawValue) · peers \(peers.count)/7 · underrun \(underrunCount) · \(linkQuality.rawValue) · rtt \(rttLabel)\(pause)"
    }

    var peerCapWarning: Bool { peers.count >= 6 }

    // MARK: Schwarm
    var fieldMap: FieldMap = .empty
    var myRole: SpeakerRole = .mid
    var calibrateProgress: Double = 0
    var calibrateStatus = ""
    var playlistTracks: [PlaylistTrack] = []
    var currentTrackID: String?
    var lightFlash: Double = 0
    var lightshowEnabled = true
    var deviceProfile = DeviceProfiler.profile()
    var proximityReady = false
    var dragProgress: CGFloat = 0

    var roleLabel: String {
        String(localized: String.LocalizationValue(myRole.titleKey))
    }

    // MARK: Internals
    private let mesh: any MeshTransporting
    private let capture = AudioCaptureEngine()
    private let playback = AudioPlaybackEngine()
    private let sessionConfig = AudioSessionConfigurator()
    private let networkPrimer = LocalNetworkPrimer()
    private let clock = ClockSync()
    private let chirp = ChirpCalibrator()
    private let