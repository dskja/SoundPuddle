import SwiftUI

struct BrandMark: View {
    var compact = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.lime.opacity(0.15))
                .frame(width: compact ? 54 : 92, height: compact ? 54 : 92)
                .scaleEffect(pulse ? 1.08 : 0.96)
            Circle()
                .stroke(Theme.lime.opacity(0.55), lineWidth: compact ? 2 : 3)
                .frame(width: compact ? 34 : 58, height: compact ? 34 : 58)
            Circle()
                .fill(Theme.lime)
                .frame(width: compact ? 12 : 18, height: compact ? 12 : 18)
        }
        .onAppear {
            guard !Motion.reduceMotion else { return }
            withAnimation(Motion.pulse) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}
