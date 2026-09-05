import SwiftUI

struct JoinLiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
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

            LevelMeter(level: model.audioLevel)
                .padding(.vertical, 28)

            Text(LocalizedStringKey(model.linkQuality.titleKey))
                .font(Theme.mono)
                .foregroundStyle(Theme.mist)

            if model.isLiveContainer && model.linkQuality != .good {
                Text(String(localized: "livecontainer.tip.audio"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.sand)
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
