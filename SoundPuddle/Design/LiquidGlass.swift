import SwiftUI

/// Liquid Glass polyfill for iOS 17–18 (CI Xcode 16). Approximates iOS 26 glass
/// with materials, specular edge light, and soft refraction highlights.
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color = .clear
    var interactive = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.glassFill)
                    if tint != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.16))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.glassHighlight.opacity(interactive ? 0.55 : 0.35),
                                    .clear,
                                    Theme.ink.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                        .opacity(0.85)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Theme.glassStroke,
                                    Theme.glassStroke.opacity(0.15),
                                    Theme.mist.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.35), radius: 18, y: 10)
    }
}

struct GlassChip: View {
    let title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? Theme.ink : Theme.textPrimary)
                .background {
                    if selected {
                        Capsule().fill(Theme.lime)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().strokeBorder(Theme.strokeGhost, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.mist)
                .frame(width: 42, height: 42)
                .background {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(Theme.strokeGhost, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear) -> some View {
        GlassSurface(cornerRadius: cornerRadius, tint: tint) { self }
    }
}
