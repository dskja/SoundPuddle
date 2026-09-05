import SwiftUI

struct LevelMeter: View {
    var level: Float
    var bars: Int = 16

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<bars, id: \.self) { i in
                let threshold = Float(i) / Float(bars)
                Capsule()
                    .fill(level > threshold ? Theme.lime : Theme.strokeGhost)
                    .frame(width: 6, height: 12 + CGFloat(i) * 2.2)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("audio.level"))
        .accessibilityValue(Text("\(Int(level * 100))%"))
    }
}
