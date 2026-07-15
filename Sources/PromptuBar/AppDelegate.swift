import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the status item, the popover, and the global hotkey.
///
/// AppKit instead of SwiftUI's MenuBarExtra because the latter has no
/// public API for opening its window programmatically, which the global
/// hotkey needs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The global hotkey summoning the panel: ⌥⌘P.
    private static let hotKeyCode = kVK_ANSI_P
    private static let hotKeyModifiers = cmdKey | optionKey

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private let session = Session()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers bundled runs; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Promptu")
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ComposerView(session: session) { [weak self] in
                self?.close()
            })

        hotKey = HotKey(keyCode: Self.hotKeyCode, modifiers: Self.hotKeyModifiers) {
            [weak self] in self?.toggle()
        }
    }

    @objc private func toggle() {
        popover.isShown ? close() : open()
    }

    private func open() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Closes the panel and hands focus back to the previous app, so a
    /// finished prompt can be pasted immediately.
    private func close() {
        popover.performClose(nil)
        NSApp.hide(nil)
    }
}
