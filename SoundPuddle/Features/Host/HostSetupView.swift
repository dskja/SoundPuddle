import SwiftUI
import UniformTypeIdentifiers

struct HostSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "host.setupTitle"))
                    .font(Theme.displayMD)
                    .foregroundStyle(Theme.textPrimary)
                Text(String(localized: "host.setupBlurb"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
                if model.showPermissionHint {
                    Text(String(localized: String.LocalizationValue(LiveContainerRuntime.hostTipKey)))
                        .font(Theme.body)
                        .foregroundStyle(Theme.sand)
                }
                if model.isLiveContainer {
                    LiveContainerBanner()
                }
                if let name = model.importedFileLabel {
                    Text(name)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.mist)
                }
            }

            TextField(String(localized: "host.titlePlaceholder"), text: $model.sessionTitle)
                .textFieldStyle(.plain)
                .font(Theme.bodyMedium)
                .padding(14)
                .glassPanel(cornerRadius: 14)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "host.pickTrack"))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                HStack(spacing: 10) {
                    sourceChip(
                        title: String(localized: "host.source.file"),
                        selected: { if case .file = model.hostSource { return true }; return false }()
                    ) { showImporter = true }
                    sourceChip(
                        title: String(localized: "host.source.mic"),
                        selected: { if case .microphone = model.hostSource { return true }; return false }()
                    ) { model.hostSource = .microphone }
                }
            }

            if let err = model.lastError {
                ErrorBanner(message: err)
            }

            Spacer()

            PuddleButton(title: String(localized: "host.open"), style: .primary) {
                model.startHosting()
            }
            PuddleButton(title: String(localized: "common.back"), style: .secondary) {
                model.goHome()
            }
        }
        .padding(28)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importAudioFile(url)
            }
        }
    }

    private func sourceChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? Theme.ink : Theme.textPrimary)
                .background(selected ? Theme.lime : Theme.well.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
