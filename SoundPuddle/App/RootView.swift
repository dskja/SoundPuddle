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
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().strokeBorder(Theme.strokeGhost, lineWidth: 1)
                    }
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
