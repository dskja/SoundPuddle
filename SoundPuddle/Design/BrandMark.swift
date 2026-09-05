import SwiftUI

struct BrandMark: View {
    var compact = false
    @State private var pulse = false
    @State private var swirl = false

    var body: some View {
        let size: CGFloat = compact ? 56 : 96
        ZStack {
            Circle()
                .fill(Theme.glowLime)
                .frame(width: size * 1.15, height: size * 1.15)
                .blur(radius: compact ? 10 : 16)
                .scaleEffect(pulse ? 1.08 : 0.92)
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.lime, Theme.mist, Theme.lime.opacity(0.2), Theme.lime],
                        center: .center
                    ),
                    lineWidth: compact ? 2 : 3
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(.degrees(swirl ? 360 : 0))
            Circle()
                .fill(Theme.lime)
                .frame(width: compact ? 12 : 18, height: compact ? 12 : 18)
                .shadow(color: Theme.lime.opacity(0.7), radius: 8)
        }
        .onAppear {
            guard !Motion.reduceMotion else { return }
            withAnimation(Motion.pulse) { pulse = true }
            withAnimation(Motion.wave) { swirl = true }
        }
        .accessibilityHidden(true)
    }
}
