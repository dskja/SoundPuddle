import SwiftUI

enum Theme {
    static let ink = Color(red: 0.018, green: 0.045, blue: 0.055)
    static let deep = Color(red: 0.035, green: 0.095, blue: 0.110)
    static let well = Color(red: 0.055, green: 0.145, blue: 0.165)
    static let lime = Color(red: 0.714, green: 0.961, blue: 0.290)
    static let mist = Color(red: 0.494, green: 0.816, blue: 0.773)
    static let sand = Color(red: 0.847, green: 0.765, blue: 0.647)
    static let danger = Color(red: 1.0, green: 0.353, blue: 0.373)
    static let textPrimary = Color(red: 0.949, green: 0.969, blue: 0.961)
    static let textMuted = Color(red: 0.541, green: 0.639, blue: 0.651)
    static let strokeGhost = Color.white.opacity(0.14)

    static let glassFill = Color.white.opacity(0.07)
    static let glassStroke = Color.white.opacity(0.28)
    static let glassHighlight = Color.white.opacity(0.40)
    static let glowLime = Color(red: 0.714, green: 0.961, blue: 0.290).opacity(0.35)

    static let display = Font.custom("Syne-Bold", size: 44, relativeTo: .largeTitle)
    static let displayMD = Font.custom("Syne-Bold", size: 28, relativeTo: .title)
    static let body = Font.custom("IBMPlexSans-Regular", size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom("IBMPlexSans-Medium", size: 17, relativeTo: .body)
    static let mono = Font.custom("IBMPlexMono-Regular", size: 13, relativeTo: .caption)
}
