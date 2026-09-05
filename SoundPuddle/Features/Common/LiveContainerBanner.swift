import SwiftUI

struct LiveContainerBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "livecontainer.badge"))
                .font(Theme.mono)
                .foregroundStyle(Theme.lime)
            Text(String(localized: "livecontainer.banner.body"))
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.strokeGhost, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
