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
    /// The app frontmost before open() stole activation, so close()
    /// can hand focus straight back without waiting out the fade.
    private var previousApp: NSRunningApplication?
    /// Closes the panel on a click in another app, installed while the
    /// popover shows. Transient behavior covers most outside clicks,
    /// but not the status bar: a click there deactivates nobody, so
    /// opening another menubar app left the panel hanging open under
    /// it. The documented contract says a global monitor sees only
    /// other processes' clicks — but in the wild (macOS 15) it also
    /// receives some of Promptu's own: panel clicks arrived carrying
    /// the panel's own window number and closed it under the user.
    /// The handler must therefore drop events aimed at our windows.
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

        // .applicationDefined, not .transient: every close is a line
        // of ours. Transient's hidden machinery was a second actor in
        // the status-click races — it can close the panel mid-click,
        // and no guard on our side can see or veto it. Its two real
        // services are replaced explicitly: deactivation (clicking
        // into another app) closes via the observer below, and
        // menubar clicks — which deactivate nobody — via the click
        // monitor (see clickMonitor).
        popover.behavior = .applicationDefined
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

        // One half of what .transient used to do: clicking into
        // another app deactivates Promptu — fold the panel. No hide:
        // focus already went where the click did. Hiding on our own
        // close (hideWhenClosed) fires this too, against an
        // already-closed popover, which performClose ignores.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // close()'s focus handoff resigns us too, mid-fade;
                // that close is already in flight (hideWhenClosed), so
                // stand down rather than re-enter performClose.
                guard let self, self.popover.isShown, !self.hideWhenClosed else { return }
                self.popover.performClose(nil)
            }
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
    /// starts with none.
    ///
    /// The menu is never shown; it exists purely to route those keys to the
    /// focused text field.
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
    private var visiblyShown: Bool {
        let win = popover.contentViewController?.view.window
        return popover.isShown && (win?.isVisible ?? false)
    }

    @objc private func toggle() {
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
        // Remember who had focus — but never Promptu itself, or a
        // wedge-recovery re-open would hand focus back to us.
        if let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            previousApp = front
        }
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
            ) { [weak self] event in
                let clickWindowNumber = event.windowNumber
                // No hide (see close): the click is taking the user
                // somewhere else, and yanking focus back would fight it.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.popover.isShown else { return }
                        // The contract violation above: an event whose
                        // window is ours is a click on Promptu itself,
                        // not the outside click this monitor exists for.
                        if NSApp.window(withWindowNumber: clickWindowNumber) != nil { return }
                        // A status-button click is the toggle's to
                        // handle, and its misdelivered copy may carry
                        // a window number that resolves to none of our
                        // windows (the menubar is not ours) — so match
                        // it by position instead and stand down.
                        if let statusWindow = self.statusItem.button?.window,
                            statusWindow.frame.contains(NSEvent.mouseLocation)
                        {
                            return
                        }
                        self.popover.performClose(nil)
                    }
                }
            }
        }
    }

    /// Closes the panel and hands focus back to the previous app, so a
    /// finished prompt can be pasted immediately. Focus moves the
    /// moment the close begins: activating the previous app leaves the
    /// fade running, where waiting for the animation's end (the old
    /// deferred-hide route) left a beat of dead time after the panel
    /// was visually gone. The deferred hide in popoverDidClose stays
    /// as the fallback for when no previous app survives to take
    /// focus — hiding *here* instead would cut the fade to a blink.
    private func close() {
        guard popover.isShown else { return NSApp.hide(nil) }
        popover.animates = Motion.enabled
        hideWhenClosed = true
        popover.performClose(nil)
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
    }
}
