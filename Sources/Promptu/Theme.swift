import SwiftUI

/// Panel colors, following the system appearance: Catppuccin Latte in
/// light mode, Nimbus in dark mode.
struct Theme {
    let background: Color
    let foreground: Color
    let dimmed: Color
    let surface: Color
    let hover: Color
    let key: Color
    let placeholder: Color
    let error: Color

    /// Catppuccin Latte (light).
    static let latte = Theme(
        background: Color(hex: 0xEFF1F5),  // base
        foreground: Color(hex: 0x4C4F69),  // text
        dimmed: Color(hex: 0x6C6F85),  // subtext0
        surface: Color(hex: 0xE6E9EF),  // mantle
        hover: Color(hex: 0xCCD0DA),  // surface0
        key: Color(hex: 0x1E66F5),  // blue
        placeholder: Color(hex: 0xFE640B),  // peach
        error: Color(hex: 0xD20F39))  // red

    /// Nimbus (dark).
    static let nimbus = Theme(
        background: Color(hex: 0x1A1A1A),  // bg
        foreground: Color(hex: 0xAAB0AB),  // fg
        dimmed: Color(hex: 0x959595),  // lighter-gray
        surface: Color(hex: 0x212121),  // fringe
        hover: Color(hex: 0x2B2B2B),  // gray-bg
        key: Color(hex: 0x70A5E1),  // light-blue
        placeholder: Color(hex: 0xDB931F),  // orange
        error: Color(hex: 0xD65946))  // red

    static func matching(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .nimbus : .latte
    }
}

/// The user's theme setting: follow the system appearance, or pin one
/// theme. Stored in UserDefaults by its raw value.
enum ThemeChoice: String, CaseIterable {
    case system, latte, nimbus

    static let defaultsKey = "theme"

    func theme(for scheme: ColorScheme) -> Theme {
        switch self {
        case .system: .matching(scheme)
        case .latte: .latte
        case .nimbus: .nimbus
        }
    }
}

extension Color {
    /// From 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
