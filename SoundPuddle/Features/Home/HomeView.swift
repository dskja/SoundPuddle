import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showNameSheet = false
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("0.0.3")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                GlassIconButton(systemName: "person.crop.circle") {
                    showNameSheet = true
                }
                .accessibilityLabel(Text("settings.displayName.title"))
            }

            Spacer(minLength: 20)

            BrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(appear ? 1 : 0.86)
                .opacity(appear ? 1 : 0)
                .padding(.bottom, 22)

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

            if model.isLiveContainer {
                LiveContainerBanner()
                    .padding(.top, 18)
            }

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
        .onAppear {
            guard !Motion.reduceMotion else { appear = true; return }
            withAnimation(Motion.brand) { appear = true }
        }
        .sheet(isPresented: $showNameSheet) {
            DisplayNameSheet()
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }
}
