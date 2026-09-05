import SwiftUI

struct JoinLiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            BrandMark(compact: true)
            Text("SoundPuddle")
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)
            Text(String(localized: "join.listening"))
                .font(Theme.mono)
                .foregroundStyle(Theme.lime)
            Text(model.sessionTitle)
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
            Text(model.roleLabel)
                .font(Theme.mono)
                .foregroundStyle(Theme.mist)
            Text(model.sessionElapsedLabel)
                .font(Theme.mono)
                .foregroundStyle(Theme.mist)

            LevelMeter(level: model.audioLevel)
                .padding(.vertical, 8)

            HStack {
                Text(LocalizedStringKey(model.linkQuality.titleKey))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.mist)
                Spacer()
                Text(model.rttLabel)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassPanel(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "join.volume"))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    GlassChip(
                        title: String(localized: model.isMuted ? "join.unmute" : "join.mute"),
                        selected: model.isMuted
                    ) { model.toggleMute() }
                }
                Slider(
                    value: Binding(
                        get: { Double(model.joinVolume) },
                        set: { model.setJoinVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(Theme.lime)
                .disabled(model.isMuted)
            }
            .padding(14)
            .glassPanel(cornerRadius: 16)

            if !model.playlistTracks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "schwarm.voteNext"))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textMuted)
                    ForEach(model.playlistTracks.prefix(4)) { track in
                        Button {
                            model.castVote(trackID: track.id)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassPanel(cornerRadius: 14)
            }

            if !model.rosterNames.isEmpty {
                Text(model.rosterNames.joined(separator: " · "))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let err = model.lastError {
                ErrorBanner(message: err)
            }

            Spacer()

            PuddleButton(title: String(localized: "join.leave"), style: .danger) {
                model.leaveSession()
            }
        }
        .padding(28)
    }
}
