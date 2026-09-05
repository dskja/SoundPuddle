import SwiftUI

struct AmbientBackground: View {
    var accent: Color = Theme.lime

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.reduceMotion ? 1.0 : 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = Motion.reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [Theme.ink, Theme.deep, Theme.well]),
                        startPoint: CGPoint(x: size.width * 0.5, y: 0),
                        endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                    )
                )

                // Soft caustic blooms
                for i in 0..<4 {
                    let phase = t * (0.18 + Double(i) * 0.05) + Double(i)
                    let cx = size.width * (0.2 + 0.2 * CGFloat(i)) + CGFloat(sin(phase)) * 36
                    let cy = size.height * (0.25 + 0.12 * CGFloat(i % 3)) + CGFloat(cos(phase * 0.8)) * 28
                    let radius = 90 + CGFloat(i) * 28
                    let glow = Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                    context.fill(glow, with: .radialGradient(
                        Gradient(colors: [accent.opacity(0.14), .clear]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 4,
                        endRadius: radius
                    ))
                }

                // Ripple bands
                for i in 0..<3 {
                    var path = Path()
                    let amp = 16 + CGFloat(i) * 9
                    let yBase = size.height * (0.58 + CGFloat(i) * 0.07)
                    let speed = 0.32 + Double(i) * 0.11
                    path.move(to: CGPoint(x: 0, y: yBase))
                    for x in stride(from: CGFloat(0), through: size.width, by: 7) {
                        let wave = sin(Double(x / 54) + t * speed + Double(i) * 1.3)
                        path.addLine(to: CGPoint(x: x, y: yBase + CGFloat(wave) * amp))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .color(accent.opacity(0.045 + Double(i) * 0.02)))
                }
            }
        }
        .ignoresSafeArea()
        .overlay {
            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 460
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay {
            // Specular wash — liquid glass atmosphere
            LinearGradient(
                colors: [Color.white.opacity(0.08), .clear, Color.black.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
