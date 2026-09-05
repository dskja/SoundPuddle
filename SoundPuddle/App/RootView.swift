import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

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
    }
}
