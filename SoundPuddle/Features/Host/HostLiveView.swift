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

            // Magic moment
            if !model.isStreaming {
                PuddleButton(title: String(localized: "host.startSchwarm"), style: .primary) {
                    model.startSchwarm()
                }
                Text(String(localized: "host.startSchwarm.blurb"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.sand)
            }

            HStack(spacing: 10) {
                GlassChip(
                    title: String(localized: model.isStreamPaused ? "host.resume" : "host.pause"),
                    selected: model.isStreamPaused
                ) { model.togglePause() }
                GlassChip(
                    title: String(localized: model.hostMonitorMuted ? "host.monitorUnmute" : "host.monitorMute"),
                    selected: !model.hostMonitorMuted
                ) { model.toggleHostMonitor() }
                GlassChip(
                    title: String(localized: model.lightshowEnabled ? "host.lightOn" : "host.lightOff"),
                    selected: model.lightshowEnabled
                ) { model.toggleLightshow() }
            }

            fieldStrip
            playlistStrip

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

    private var fieldStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "schwarm.field"))
                .font(Theme.mono)
                .foregroundStyle(Theme.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.fieldMap.seats) { seat in
                        Text("\(seat.name) · \(String(localized: String.LocalizationValue(seat.role.titleKey)))")
                            .font(Theme.mono)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }

    private var playlistStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "schwarm.playlist"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Button(String(localized: "schwarm.advance")) {
                    model.advancePlaylist()
                }
                .font(Theme.mono)
                .foregroundStyle(Theme.lime)
            }
            ForEach(model.playlistTracks.prefix(4)) { track in
                Button {
                    model.hostVote(trackID: track.id)
                } label: {
                    HStack {
                        Text(track.title)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(track.votes)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.mist)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }
}
