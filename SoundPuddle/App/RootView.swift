import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AmbientBackground()
            Group {
                switch model.route {
                case .home:
                    HomeView()
                case .hostSetup:
                    HostSetupView()
                case .hostLive:
                    HostLiveView()
                case .joinBrowse:
                    JoinDiscoverView()
                case .joinConnecting:
                    JoinConnectingView()
                case .joinLive:
                    JoinLiveView()
                }
            }
            .transition(.opacity)
        }
        .animation(Motion.route, value: model.route)
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
        .overlay(alignment: .top) {
            if model.route == .hostLive || model.route == .joinLive {
                Text(model.diagnosticsLine)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.ink.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
