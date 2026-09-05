import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 14, tint: Theme.danger)
    }
}
