import SwiftUI

struct JoinDiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "join.nearby"))
                .font(Theme.displayMD)
                .foregroundStyle(Theme.textPrimary)

            if model.showPermissionHint {
                Text(String(localized: String.LocalizationValue(LiveContainerRuntime.joinTipKey)))
                    .font(Theme.body)
                    .foregroundStyle(Theme.sand)
            }
            if model.isLiveContainer {
                LiveContainerBanner()
            }

            if model.isLiveContainer {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "join.code.title"))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textMuted)
                    TextField(String(localized: "join.code.placeholder"), text: Bindable(model).manualJoinAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(Theme.displayMD)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(String(localized: "join.code.blurb"))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.sand)
                        .fixedSize(horizontal: false, vertical: true)
                    PuddleButton(title: String(localized: "join.code.connect"), style: .primary) {
                        model.joinWithManualAddress()
                    }
                }
            }

            Text(String(localized: "join.dragHint"))
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)

            ZStack {
                Circle()
                    .strokeBorder(Theme.lime.opacity(0.35 + model.dragProgress * 0.5), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(0.85 + model.dragProgress * 0.2)
                BrandMark(compact: true)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                                let dist = hypot(value.translation.width, value.translation.height)
                                model.setDragProgress(max(0, 1 - dist / 160))
                            }
                            .onEnded { _ in
                                withAnimation(Motion.snappy) { dragOffset = .zero }
                                if model.proximityReady, let first = model.discovered.first {
                                    model.join(peer: first.peer, advertisement: first.ad)
                                }
                                model.setDragProgress(0)
                            }
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            if model.discovered.isEmpty {
                Text(String(localized: "join.empty"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
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
                                    Text(item.peer.displayName)
                                        .font(Theme.mono)
                                        .foregroundStyle(Theme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
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
