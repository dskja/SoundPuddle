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
                case .joinCalibrate:
                    JoinCalibrateView()
                case .joinLive:
                    JoinLiveView()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.985)))

            if model.lightFlash > 0.02 {
                Theme.lime.opacity(model.lightFlash * 0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: model.lightFlash)
            }
        }
        .animation(Motion.route, value: model.route)
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
        .overlay(alignment: .top) {
            if model.route == .hostLive || model.route == .joinLive || model.route == .joinCalibrate {
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
