import SwiftUI

enum Theme {
    static let ink = Color(red: 0.027, green: 0.059, blue: 0.071)
    static let deep = Color(red: 0.043, green: 0.110, blue: 0.122)
    static let well = Color(red: 0.063, green: 0.165, blue: 0.180)
    static let lime = Color(red: 0.714, green: 0.961, blue: 0.290)
    static let mist = Color(red: 0.494, green: 0.816, blue: 0.773)
    static let sand = Color(red: 0.847, green: 0.765, blue: 0.647)
    static let danger = Color(red: 1.0, green: 0.353, blue: 0.373)
    static let textPrimary = Color(red: 0.949, green: 0.969, blue: 0.961)
    static let textMuted = Color(red: 0.541, green: 0.639, blue: 0.651)
    static let strokeGhost = Color.white.opacity(0.12)

    static let display = Font.custom("Syne-Bold", size: 44, relativeTo: .largeTitle)
    static let displayMD = Font.custom("Syne-Bold", size: 28, relativeTo: .title)
    static let body = Font.custom("IBMPlexSans-Regular", size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom("IBMPlexSans-Medium", size: 17, relativeTo: .body)
    static let mono = Font.custom("IBMPlexMono-Regular", size: 13, relativeTo: .caption)
}
