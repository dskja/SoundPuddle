import SwiftUI

struct JoinDiscoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "join.nearby"))
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)

            if model.showPermissionHint {
                Text(String(localized: "permission.join.body"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.sand)
            }

            if model.discovered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    BrandMark(compact: true)
                    Text(String(localized: "join.empty"))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.discovered.enumerated()), id: \.element.peer.id) { index, item in
                            Button {
                                model.join(peer: item.peer, advertisement: item.ad)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.ad.title)
                                        .font(Theme.bodyMedium)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(String(localized: String.LocalizationValue(item.ad.mode.titleKey))) · \(item.peer.displayName)")
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .opacity(1)
                            .animation(Motion.route.delay(Double(index) * 0.04), value: model.discovered.count)
                            if index < model.discovered.count - 1 {
                                Divider().overlay(Theme.strokeGhost)
                            }
                        }
                    }
                }
            }

            if let err = model.lastError {
                ErrorBanner(message: err)
            }

            Spacer()

            PuddleButton(title: String(localized: "join.refresh"), style: .secondary) {
                model.startBrowsing()
            }
            PuddleButton(title: String(localized: "common.back"), style: .secondary) {
                model.goHome()
            }
        }
        .padding(28)
    }
}
