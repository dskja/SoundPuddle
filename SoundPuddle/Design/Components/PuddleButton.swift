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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(border, lineWidth: style == .secondary ? 1 : 0)
                }
                .shadow(color: style == .primary ? Theme.lime.opacity(0.28) : .clear, radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary: return Theme.ink
        case .secondary, .danger: return Theme.textPrimary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            LinearGradient(colors: [Theme.lime, Theme.lime.opacity(0.82)], startPoint: .top, endPoint: .bottom)
        case .secondary:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                Theme.glassFill
            }
        case .danger:
            Theme.danger.opacity(0.88)
        }
    }

    private var border: Color {
        style == .secondary ? Theme.strokeGhost : .clear
    }
}
