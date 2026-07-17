import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Owns the status item, the popover, and the global hotkey.
///
/// AppKit instead of SwiftUI's MenuBarExtra because the latter has no
/// public API for opening its window programmatically, which the global
/// hotkey needs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private let session = Session()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers bundled runs; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        registerLoginItemOnce()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Promptu")
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: ComposerView(session: session) { [weak self] in
                self?.close()
            })
        // Track the SwiftUI ideal size, so the popover grows and shrinks
        // with the preview instead of staying at its first-shown size.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        registerHotKey()
        NotificationCenter.default.addObserver(
            forName: .hotKeyReload, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }
        NotificationCenter.default.addObserver(
            forName: .hotKeySuspend, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotKey = nil }
        }
    }

    /// Register as a login item on the first launch from /Applications,
    /// so installs start at login by default. The settings toggle (or
    /// System Settings → Login Items) turns it off afterwards; the
    /// one-shot flag keeps that choice from being overridden. Dev runs
    /// from a checkout are skipped so they never pin themselves.
    private func registerLoginItemOnce() {
        guard !UserDefaults.standard.bool(forKey: "loginItemApplied"),
            Bundle.main.bundlePath.hasPrefix("/Applications/")
        else { return }
        UserDefaults.standard.set(true, forKey: "loginItemApplied")
        try? SMAppService.mainApp.register()
    }

    /// (Re)register the global hotkey from its saved setting; replacing
    /// the HotKey unregisters the old combination via its deinit.
    private func registerHotKey() {
        let spec = HotKeySpec.load()
        hotKey = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers) {
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
