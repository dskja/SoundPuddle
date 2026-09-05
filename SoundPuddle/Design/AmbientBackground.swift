import SwiftUI

struct AmbientBackground: View {
    var accent: Color = Theme.lime

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.reduceMotion ? 1.0 : 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = Motion.reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Theme.ink, Theme.deep, Theme.well]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                ))

                for i in 0..<3 {
                    var path = Path()
                    let amp = 18 + CGFloat(i) * 10
                    let yBase = size.height * (0.55 + CGFloat(i) * 0.08)
                    let speed = 0.35 + Double(i) * 0.12
                    path.move(to: CGPoint(x: 0, y: yBase))
                    for x in stride(from: CGFloat(0), through: size.width, by: 8) {
                        let wave = sin(Double(x / 60) + t * speed + Double(i))
                        let y = yBase + CGFloat(wave) * amp
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .color(accent.opacity(0.05 + Double(i) * 0.02)))
                }
            }
        }
        .ignoresSafeArea()
        .overlay {
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
