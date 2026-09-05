import SwiftUI

struct JoinConnectingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandMark()
            Text(String(localized: "join.connecting"))
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)
            Text(model.sessionTitle)
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
            Spacer()
            PuddleButton(title: String(localized: "common.cancel"), style: .secondary) {
                model.goHome()
            }
        }
        .padding(28)
    }
}
