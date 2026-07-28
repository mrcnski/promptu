import AppKit
import Carbon.HIToolbox
import Combine
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
    private let updateChecker = UpdateChecker()
    private var updateObserver: AnyCancellable?
    /// A small dot on the status icon, shown while an update is
    /// available, overlaid as a subview so the icon stays a template
    /// image that tints with the menubar.
    private let updateDot: NSView = {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.backgroundColor =
            NSColor(red: 0.87, green: 0.56, blue: 0.11, alpha: 1).cgColor  // yellow
        dot.layer?.cornerRadius = 3
        dot.isHidden = true
        return dot
    }()
    /// Set while close() waits out the popover's close animation: the
    /// app hides — handing focus back — only once it has played,
    /// where hiding immediately would cut it to a blink.
    private var hideWhenClosed = false
    /// Closes the panel on a click in another app, installed while the
    /// popover shows. Transient behavior covers most outside clicks,
    /// but not the status bar: a click there deactivates nobody, so
    /// opening another menubar app left the panel hanging open under
    /// it. A global monitor sees exactly the missing clicks — they
    /// belong to other processes; Promptu's own (the popover, the
    /// status button) never reach it, so toggling is untouched.
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement covers bundled runs; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        // A steady caret instead of the system's ~1Hz pulse: every
        // pulse dirties the panel, and the window-plus-shadow repaint
        // reads as a faint whole-panel shimmer over dark backdrops.
        UserDefaults.standard.set(100_000, forKey: "NSTextInsertionPointBlinkPeriodOn")
        UserDefaults.standard.set(0, forKey: "NSTextInsertionPointBlinkPeriodOff")

        // Tooltips on hover rather than after the system's multi-second
        // dwell. A tooltip here explains a control the user is already
        // pointing at; waiting that long reads as nothing happening.
        // Their fade-out is drawn by the system and can't be tuned.
        UserDefaults.standard.set(150, forKey: "NSInitialToolTipDelay")

        installEditMenu()
        registerLoginItemOnce()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Promptu")
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self
        if let button = statusItem.button {
            button.addSubview(updateDot)
            updateDot.frame.origin = NSPoint(x: button.bounds.maxX - 8, y: button.bounds.maxY - 8)
            updateDot.autoresizingMask = [.minXMargin, .minYMargin]
        }

        // Reflect an available update onto the status badge.
        updateObserver = updateChecker.$available.sink { [weak self] update in
            self?.updateDot.isHidden = update == nil
        }

        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: ComposerView(session: session, updateChecker: updateChecker) {
                [weak self] in self?.close()
            })
        // Track the SwiftUI ideal size, so the popover grows and shrinks
        // with the preview instead of staying at its first-shown size.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        // A pinned theme must reach the popover's own chrome: the
        // content colors itself, but the frame — the arrow above the
        // panel — is drawn from the window's appearance, and left
        // alone it follows the system. Nimbus on a light system then
        // wore a light arrow on a dark panel. Re-applied on every
        // defaults write; the theme setting has no channel of its own.
        applyThemeAppearance()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyThemeAppearance() }
        }

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

        updateChecker.checkIfDue()
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

    /// Match the popover's appearance to the theme setting: nil for
    /// "system" (inherit), forced light or dark for a pinned theme.
    /// Compared by name before assigning — the defaults observer calls
    /// this on every write, and re-assigning an equal appearance would
    /// still dirty the shown panel.
    private func applyThemeAppearance() {
        let choice =
            ThemeChoice(
                rawValue: UserDefaults.standard.string(forKey: ThemeChoice.defaultsKey) ?? ""
            ) ?? .system
        let appearance: NSAppearance? =
            switch choice {
            case .system: nil
            case .latte: NSAppearance(named: .aqua)
            case .nimbus: NSAppearance(named: .darkAqua)
            }
        if popover.appearance?.name != appearance?.name {
            popover.appearance = appearance
        }
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
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        let hide = hideWhenClosed
        hideWhenClosed = false
        DispatchQueue.main.async { [weak self] in
            self?.registerHotKey()
            self?.updateChecker.panelDidClose()
            if hide { NSApp.hide(nil) }
        }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        // Re-read per open/close, so the settings toggle applies live.
        popover.animates = Motion.enabled
        updateChecker.panelWillOpen()
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
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                // No hide (see close): the click is taking the user
                // somewhere else, and yanking focus back would fight it.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.popover.isShown else { return }
                        self.popover.performClose(nil)
                    }
                }
            }
        }
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
