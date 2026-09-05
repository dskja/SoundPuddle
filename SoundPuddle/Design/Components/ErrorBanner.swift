import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.danger.opacity(0.6), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
