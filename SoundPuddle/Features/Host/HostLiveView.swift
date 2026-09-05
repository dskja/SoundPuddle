import SwiftUI

struct HostLiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sessionTitle)
                        .font(Theme.displayMD)
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.sessionElapsedLabel)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.mist)
                }
                Spacer()
                Text("PEER \(String(format: "%02d", model.peers.count))/07")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.mist)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            LevelMeter(level: model.audioLevel)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                GlassChip(
                    title: String(localized: model.isStreamPaused ? "host.resume" : "host.pause"),
                    selected: model.isStreamPaused
                ) { model.togglePause() }
                GlassChip(
                    title: String(localized: model.hostMonitorMuted ? "host.monitorUnmute" : "host.monitorMute"),
                    selected: !model.hostMonitorMuted
                ) { model.toggleHostMonitor() }
            }

            if model.isStreamPaused {
                Text(String(localized: "host.pausedBanner"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.sand)
                    .padding(12)
                    .glassPanel(cornerRadius: 14, tint: Theme.sand)
            }

            if model.peerCapWarning {
                Text(String(localized: "host.capacityWarning"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.sand)
            }

            if model.linkQuality == .weak {
                Text(String(localized: "link.weak"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.danger)
            }

            if model.isLiveContainer && model.linkQuality != .good {
                Text(String(localized: "livecontainer.tip.audio"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.sand)
            }

            Text(String(localized: "host.peers"))
                .font(Theme.mono)
                .foregroundStyle(Theme.textMuted)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.peers) { peer in
                        Text("• \(peer.displayName)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            if let err = model.lastError {
                ErrorBanner(message: err)
            }

            Spacer(minLength: 0)

            PuddleButton(title: String(localized: "host.stop"), style: .danger) {
                model.stopHosting()
            }
        }
        .padding(28)
    }
}
