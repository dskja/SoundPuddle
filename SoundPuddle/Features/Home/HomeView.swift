import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 48)
            BrandMark()
                .padding(.bottom, 28)
            Text("SoundPuddle")
                .font(Theme.display)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "home.headline"))
                .font(Theme.displayMD)
                .foregroundStyle(Theme.lime)
                .padding(.top, 10)
            Text(String(localized: "home.subhead"))
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 12) {
                PuddleButton(title: String(localized: "home.host"), style: .primary) {
                    model.openHost()
                }
                PuddleButton(title: String(localized: "home.join"), style: .secondary) {
                    model.openJoin()
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
    }
}
