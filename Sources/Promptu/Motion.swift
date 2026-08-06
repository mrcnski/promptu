import SwiftUI

/// The animations setting: when off, every animated change applies instantly.
enum Motion {
    private static let key = "disableAnimations"

    static var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(!newValue, forKey: key) }
    }

    /// The animation to run under the setting: nil (instant) when off.
    static func gated(_ animation: Animation) -> Animation? {
        enabled ? animation : nil
    }
}
