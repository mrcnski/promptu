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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private let session = Session()
    /// Set while close() waits out the popover's close animation: the
    /// app hides — handing focus back — only once it has played,
    /// where hiding immediately would cut it to a blink.
    private var hideWhenClosed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers bundled runs; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        // A steady caret instead of the system's ~1Hz pulse: every
        // pulse dirties the panel, and the window-plus-shadow repaint
        // reads as a faint whole-panel shimmer over dark backdrops.
        UserDefaults.standard.set(100_000, forKey: "NSTextInsertionPointBlinkPeriodOn")
        UserDefaults.standard.set(0, forKey: "NSTextInsertionPointBlinkPeriodOff")

        installEditMenu()
        registerLoginItemOnce()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Promptu")
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.delegate = self
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

    /// Editing shortcuts (⌘C, ⌘V, ⌘A, undo…) only work when a main menu
    /// defines their key equivalents, and a programmatic accessory app
    /// starts with none. The menu is never shown; it exists purely to
    /// route those keys to the focused text field.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let bar = NSMenu()
        let item = NSMenuItem()
        item.submenu = edit
        bar.addItem(item)
        NSApp.mainMenu = bar
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

    /// (Re)register the global hotkey from its saved setting. The old
    /// registration must go first: registering a combination that is
    /// still registered fails, and the stale one would then unregister
    /// on release — leaving no hotkey at all.
    private func registerHotKey() {
        hotKey = nil
        let spec = HotKeySpec.load()
        hotKey = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers) {
            [weak self] in self?.toggle()
        }
    }

    /// Treat a popover that claims to be shown but has no visible
    /// window as closed: reopening clears the wedge (seen once in the
    /// wild — show succeeded invisibly and every other press then
    /// toggled a phantom), where closing it would just hide the app.
    @objc private func toggle() {
        let win = popover.contentViewController?.view.window
        let visiblyShown = popover.isShown && (win?.isVisible ?? false)
        visiblyShown ? close() : open()
    }

    /// A popover closed while the settings recorder was capturing (a
    /// click outside, say) never runs the recorder's cleanup, which
    /// would leave the hotkey suspended for good. Re-registering is
    /// cheap and idempotent, so just always do it on close.
    ///
    /// Deferred to the next runloop turn: with animations off this
    /// delegate fires synchronously inside the hotkey's own Carbon
    /// dispatch, and re-registering there would RemoveEventHandler on
    /// the handler still executing — killing the hotkey after one use.
    func popoverDidClose(_ notification: Notification) {
        let hide = hideWhenClosed
        hideWhenClosed = false
        DispatchQueue.main.async { [weak self] in
            self?.registerHotKey()
            if hide { NSApp.hide(nil) }
        }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        // Re-read per open/close, so the settings toggle applies live.
        popover.animates = Motion.enabled
        // A wedged (shown-but-invisible) popover must be fully closed
        // before show, or show is a no-op against the phantom.
        if popover.isShown { popover.performClose(nil) }
        // Forced activation, after unhiding (close hides the app):
        // macOS denies an accessory app's cooperative NSApp.activate(),
        // leaving the previous app frontmost under the popover, and
        // frontmost-scoped tools then act on the wrong target while the
        // user types here. The deprecation claims the flag has no
        // effect; empirically (macOS 15.7) it is the one call that
        // works.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Closes the panel and hands focus back to the previous app, so a
    /// finished prompt can be pasted immediately. The hide waits for
    /// the close animation (see popoverDidClose) — hiding here would
    /// cut it to a blink.
    private func close() {
        guard popover.isShown else { return NSApp.hide(nil) }
        popover.animates = Motion.enabled
        hideWhenClosed = true
        popover.performClose(nil)
    }
}
