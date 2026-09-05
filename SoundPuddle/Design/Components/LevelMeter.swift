import SwiftUI

struct LevelMeter: View {
    var level: Float
    var bars: Int = 18

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let threshold = Float(i) / Float(bars)
                let active = level > threshold
                Capsule()
                    .fill(
                        active
                        ? LinearGradient(colors: [Theme.mist, Theme.lime], startPoint: .bottom, endPoint: .top)
                        : LinearGradient(colors: [Theme.strokeGhost, Theme.strokeGhost], startPoint: .bottom, endPoint: .top)
                    )
                    .frame(width: 5, height: 10 + CGFloat(i) * 2.1)
                    .shadow(color: active ? Theme.lime.opacity(0.35) : .clear, radius: 4)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .glassPanel(cornerRadius: 18, tint: Theme.lime)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("audio.level"))
        .accessibilityValue(Text("\(Int(level * 100))%"))
    }
}
