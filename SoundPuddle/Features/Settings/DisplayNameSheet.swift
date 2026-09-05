import SwiftUI

struct DisplayNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "settings.displayName.help"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
                TextField(String(localized: "settings.displayName.placeholder"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyMedium)
                    .padding(14)
                    .background(Theme.well.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                PuddleButton(title: String(localized: "settings.displayName.save"), style: .primary) {
                    model.updateDisplayName(draft)
                    dismiss()
                }
            }
            .padding(24)
            .navigationTitle(String(localized: "settings.displayName.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .onAppear { draft = model.displayName }
            .background(Theme.ink.ignoresSafeArea())
        }
    }
}
