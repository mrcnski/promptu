import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// In-popover settings: the theme choice, the global hotkey, and
/// launch at login.
struct SettingsView: View {
    let theme: Theme
    @AppStorage(ThemeChoice.defaultsKey) private var themeChoice = ThemeChoice.system
    @State private var hotKeyDisplay = HotKeySpec.load().display
    @State private var recording = false
    @State private var recordingError: String?
    @State private var monitor: Any?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { stopRecording() }
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
