import SwiftUI

struct AmbientBackground: View {
    @State private var phase: CGFloat = 0
    var accent: Color = Theme.lime

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.reduceMotion ? 1 : 1 / 30)) { timeline in
            Canvas { context, size in
                let t = Motion.reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
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
                    for x in stride(from: 0, through: size.width, by: 8) {
                        let y = yBase + sin((x / 60) + t * speed + Double(i)) * amp
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
