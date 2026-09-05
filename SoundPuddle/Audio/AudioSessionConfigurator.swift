import AVFoundation

final class AudioSessionConfigurator {
    func configure(for mode: SessionMode, role: MeshRole) throws {
        let session = AVAudioSession.sharedInstance()
        switch (mode, role) {
        case (.tour, .host):
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        case (_, .host):
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        case (_, .join):
            var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
            if LiveContainerRuntime.isActive {
                options.insert(.mixWithOthers)
            }
            try session.setCategory(.playback, mode: .default, options: options)
        }
        try session.setPreferredSampleRate(AudioFormatSpec.canonical.sampleRate)
        try session.setActive(true, options: [])
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

enum MeshRole: String, Sendable {
    case host
    case join
}
