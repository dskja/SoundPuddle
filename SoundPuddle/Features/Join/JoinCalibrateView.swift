import SwiftUI

struct JoinCalibrateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            BrandMark(compact: true)
            Text(String(localized: "calibrate.title"))
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)
            Text(model.calibrateStatus.isEmpty
                 ? String(localized: "calibrate.syncing")
                 : model.calibrateStatus)
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            ProgressView(value: model.calibrateProgress)
                .tint(Theme.lime)
                .padding(.horizontal, 24)

            Text(String(localized: "calibrate.holdStill"))
                .font(Theme.mono)
                .foregroundStyle(Theme.sand)

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
