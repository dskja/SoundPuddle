import SwiftUI

struct PuddleButton: View {
    enum Style { case primary, secondary, danger }

    let title: String
    var style: Style = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(foreground)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.strokeGhost, lineWidth: style == .secondary ? 1 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary: return Theme.ink
        case .secondary: return Theme.textPrimary
        case .danger: return Theme.textPrimary
        }
    }

    private var background: Color {
        switch style {
        case .primary: return Theme.lime
        case .secondary: return Theme.well.opacity(0.7)
        case .danger: return Theme.danger.opacity(0.85)
        }
    }
}
