import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// In-popover settings: the theme choice, animations, the global
/// hotkey, launch at login, prompt history, and the update check —
/// including the running version and a check that can be started by
/// hand.
struct SettingsView: View {
    let theme: Theme
    @ObservedObject var session: Session
    @ObservedObject var updateChecker: UpdateChecker
    /// Whether the clear button is showing its confirmation. Clearing
    /// can't be undone, so it takes two clicks; the label swaps in
    /// place, leaving the row's height alone.
    @State private var confirmClear = false
    @AppStorage(ThemeChoice.defaultsKey) private var themeChoice = ThemeChoice.system
    @State private var hotKeyDisplay = HotKeySpec.load().display
    @State private var recording = false
    @State private var recordingError: String?
    @State private var monitor: Any?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var animationsOn = Motion.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("theme").font(.caption).foregroundStyle(theme.dimmed)
            HStack(spacing: 2) {
                ForEach(ThemeChoice.allCases, id: \.self) { choice in
                    Button { themeChoice = choice } label: {
                        Text(choice.rawValue)
                            .font(choice == themeChoice ? .callout.bold() : .callout)
                            .foregroundStyle(choice == themeChoice ? theme.key : theme.dimmed)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                }
            }

            Text("animations").font(.caption).foregroundStyle(theme.dimmed)
            HStack(spacing: 2) {
                ForEach([true, false], id: \.self) { on in
                    Button {
                        Motion.enabled = on
                        animationsOn = on
                    } label: {
                        Text(on ? "on" : "off")
                            .font(on == animationsOn ? .callout.bold() : .callout)
                            .foregroundStyle(on == animationsOn ? theme.key : theme.dimmed)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                }
            }

            Text("hotkey").font(.caption).foregroundStyle(theme.dimmed)
            HStack(spacing: 6) {
                if recording {
                    Text("press the new hotkey…")
                        .font(.callout)
                        .foregroundStyle(theme.placeholder)
                } else {
                    Text(hotKeyDisplay)
                        .font(.callout.monospaced().bold())
                        .foregroundStyle(theme.foreground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 5))
                    Button { startRecording() } label: {
                        Text("change").font(.callout).foregroundStyle(theme.key)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                }
            }
            if let error = recordingError {
                Text(error).font(.caption).foregroundStyle(theme.error)
            }

            Text("launch at login").font(.caption).foregroundStyle(theme.dimmed)
            HStack(spacing: 2) {
                ForEach([true, false], id: \.self) { on in
                    Button { setLaunchAtLogin(on) } label: {
                        Text(on ? "on" : "off")
                            .font(on == launchAtLogin ? .callout.bold() : .callout)
                            .foregroundStyle(on == launchAtLogin ? theme.key : theme.dimmed)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                }
            }
            if let error = loginError {
                Text(error).font(.caption).foregroundStyle(theme.error)
            }

            Text("remember prompts").font(.caption).foregroundStyle(theme.dimmed)
            // The note belongs to the switch above it, not to the
            // section below: every label in this panel is a dimmed
            // caption with the full spacing around it, so the note
            // hugs its own row and sits a size smaller to keep from
            // reading as the next one's heading.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    ForEach([true, false], id: \.self) { on in
                        Button { session.setHistoryOn(on) } label: {
                            Text(on ? "on" : "off")
                                .font(on == session.historyOn ? .callout.bold() : .callout)
                                .foregroundStyle(
                                    on == session.historyOn ? theme.key : theme.dimmed)
                        }
                        .buttonStyle(HoverButtonStyle(theme: theme))
                    }
                    Spacer()
                    Text(historyCount)
                        .font(.caption)
                        .foregroundStyle(theme.dimmed)
                    // The one destructive control in the panel, so it
                    // asks once; the whole row is grayed out with
                    // nothing to clear.
                    Button {
                        if confirmClear {
                            session.clearHistory()
                            confirmClear = false
                        } else {
                            confirmClear = true
                        }
                    } label: {
                        Text(confirmClear ? "click again to clear" : "clear")
                            .font(.callout)
                            .foregroundStyle(confirmClear ? theme.error : theme.key)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                    .opacity(session.history.isEmpty ? 0.4 : 1)
                    .allowsHitTesting(!session.history.isEmpty)
                }
                // Plain, because a copied prompt carries whatever was
                // typed into its placeholders.
                Text("kept on this Mac in plain text, values included")
                    .font(.caption2)
                    .foregroundStyle(theme.dimmed.opacity(0.75))
                    .padding(.leading, 6)
            }

            Text("check for updates").font(.caption).foregroundStyle(theme.dimmed)
            HStack(spacing: 2) {
                ForEach([true, false], id: \.self) { on in
                    Button { updateChecker.setEnabled(on) } label: {
                        Text(on ? "on" : "off")
                            .font(on == updateChecker.enabled ? .callout.bold() : .callout)
                            .foregroundStyle(
                                on == updateChecker.enabled ? theme.key : theme.dimmed)
                    }
                    .buttonStyle(HoverButtonStyle(theme: theme))
                }
            }

            Text("version").font(.caption).foregroundStyle(theme.dimmed)
            // The check-now button is the tallest thing in this row and
            // is always present, so the status text swapping between
            // its states never changes the row's height — a height
            // change here would resize the popover and flash the panel.
            HStack(spacing: 8) {
                Text(UpdateChecker.currentVersion)
                    .font(.callout.monospaced().bold())
                    .foregroundStyle(theme.foreground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 5))
                updateStatus
                Spacer()
                // Grayed out rather than hidden while the check is off:
                // off means no pings to GitHub, by hand or otherwise.
                Button { updateChecker.checkNow() } label: {
                    Text("check now").font(.callout).foregroundStyle(theme.key)
                }
                .buttonStyle(HoverButtonStyle(theme: theme))
                .opacity(updateChecker.enabled ? 1 : 0.4)
                .allowsHitTesting(updateChecker.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            stopRecording()
            confirmClear = false
        }
    }

    /// How much history is stored, beside the clear button.
    private var historyCount: String {
        let count = session.history.count
        return count == 1 ? "1 prompt" : "\(count) prompts"
    }

    /// What the last check found, beside the version. A known update
    /// wins over a failed check: the cached answer is still the useful
    /// one, and the failure is only about its age.
    @ViewBuilder private var updateStatus: some View {
        if !updateChecker.enabled {
            statusText("checks off")
        } else if updateChecker.status == .checking {
            statusText("checking…")
        } else if let update = updateChecker.latestKnown {
            Button { NSWorkspace.shared.open(update.url) } label: {
                Text("v\(update.version) available →")
                    .font(.caption)
                    .foregroundStyle(theme.notice)
            }
            .buttonStyle(HoverButtonStyle(theme: theme, horizontalPadding: 4))
            .help(lastCheckHelp)
        } else if updateChecker.status == .failed {
            statusText("check failed")
        } else if updateChecker.lastCheck == nil {
            statusText("not checked yet")
        } else {
            statusText("up to date")
        }
    }

    private func statusText(_ label: String) -> some View {
        Text(label).font(.caption).foregroundStyle(theme.dimmed).help(lastCheckHelp)
    }

    /// The status's tooltip: how old the answer is.
    private var lastCheckHelp: String {
        guard let date = updateChecker.lastCheck else { return "no successful check yet" }
        return "last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Capture the next keypress as the hotkey. The global hotkey is
    /// suspended meanwhile, so its current combination can be recorded
    /// again instead of toggling the panel.
    private func startRecording() {
        recording = true
        NotificationCenter.default.post(name: .hotKeySuspend, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecorded(event)
            return nil  // Swallow the press; it must not reach the view.
        }
    }

    private func handleRecorded(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isDisjoint(with: [.command, .option, .control]) else {
            recordingError = "include ⌘, ⌥, or ⌃"
            return
        }
        let spec = HotKeySpec(
            keyCode: Int(event.keyCode),
            modifiers: HotKeySpec.carbonModifiers(flags),
            display: HotKeySpec.display(flags, key: event.charactersIgnoringModifiers ?? "?"))
        spec.save()
        hotKeyDisplay = spec.display
        stopRecording()
    }

    /// End recording (with or without a new hotkey saved), drop any
    /// mid-recording error, and re-register from the stored spec.
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        recordingError = nil
        NotificationCenter.default.post(name: .hotKeyReload, object: nil)
    }
}
