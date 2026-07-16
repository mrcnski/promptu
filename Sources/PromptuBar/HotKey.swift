import AppKit
import Carbon.HIToolbox
import Foundation

/// The user's global hotkey, persisted in UserDefaults; ⌥⌘P until
/// changed in the settings screen.
struct HotKeySpec: Equatable {
    var keyCode: Int
    /// Carbon modifier mask (cmdKey etc.), as RegisterEventHotKey wants.
    var modifiers: Int
    var display: String

    static let `default` = HotKeySpec(
        keyCode: kVK_ANSI_P, modifiers: cmdKey | optionKey, display: "⌥⌘P")

    static func load(from defaults: UserDefaults = .standard) -> HotKeySpec {
        guard let keyCode = defaults.object(forKey: "hotKeyCode") as? Int,
            let modifiers = defaults.object(forKey: "hotKeyModifiers") as? Int,
            let display = defaults.string(forKey: "hotKeyDisplay")
        else { return .default }
        return HotKeySpec(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(keyCode, forKey: "hotKeyCode")
        defaults.set(modifiers, forKey: "hotKeyModifiers")
        defaults.set(display, forKey: "hotKeyDisplay")
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return mask
    }

    static func display(_ flags: NSEvent.ModifierFlags, key: String) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out + key.uppercased()
    }
}

extension Notification.Name {
    /// Unregister the global hotkey while the recorder captures keys.
    static let hotKeySuspend = Notification.Name("hotKeySuspend")
    /// (Re)register the global hotkey from the saved spec.
    static let hotKeyReload = Notification.Name("hotKeyReload")
}

/// A single global hotkey registered with Carbon's RegisterEventHotKey,
/// which needs no accessibility permissions and swallows the key
/// system-wide while the app runs.
@MainActor
final class HotKey {
    // nonisolated(unsafe): written once in init, read in deinit; both
    // effectively main-thread.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init(keyCode: Int, modifiers: Int, onPress: @escaping () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hotkey events on the main thread.
                MainActor.assumeIsolated { hotKey.onPress() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: OSType(0x504D5455), id: 1),  // "PMTU"
            GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("promptu-app: hotkey registration failed (OSStatus %d)", status)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
