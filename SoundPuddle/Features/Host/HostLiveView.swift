import SwiftUI

struct HostLiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.sessionTitle)
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)
            Text("PEER \(String(format: "%02d", model.peers.count))/07")
                .font(Theme.mono)
                .foregroundStyle(Theme.mist)

            LevelMeter(level: model.audioLevel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

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
