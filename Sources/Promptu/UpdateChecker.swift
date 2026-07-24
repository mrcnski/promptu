import Foundation
import PromptuCore

/// Polls the GitHub Releases API for a newer version and, when one is
/// found, surfaces it as `available` for the composer's notice row and
/// the menubar badge. The check is opt-out (it pings GitHub with the
/// user's IP), throttled to once a day, and silent on any failure —
/// offline or rate-limited means no notice, never an error.
@MainActor
final class UpdateChecker: ObservableObject {
    /// A newer release than the running build.
    struct Update: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var available: Update?
    /// Whether the periodic check runs; off stops the GitHub pings.
    /// Published rather than read from UserDefaults on demand, so the
    /// settings toggle renders it right on its first frame.
    @Published private(set) var enabled: Bool

    private let disabledKey = "updateCheckDisabled"
    private let lastCheckKey = "updateLastCheck"
    private let latestVersionKey = "updateLatestVersion"
    private let latestURLKey = "updateLatestURL"
    private let dismissedKey = "updateDismissedVersion"

    /// Once a day; the API allows 60 unauthenticated calls an hour, so
    /// the interval is about caution, not the limit.
    private let interval: TimeInterval = 24 * 60 * 60
    private let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/mrcnski/promptu/releases/latest")!

    private let defaults = UserDefaults.standard

    /// True while the panel is showing. A poll that lands during this
    /// window only updates the cache — surfacing a freshly found update
    /// then would pop the banner in under the user, shifting the
    /// content and resizing the popover mid-view.
    private var panelIsOpen = false

    init() {
        enabled = !defaults.bool(forKey: disabledKey)
        // Surface a previously fetched result immediately, before any
        // network round-trip — the notice shouldn't wait for the poll.
        refreshAvailable()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(!on, forKey: disabledKey)
        if on {
            checkIfDue()
        } else {
            available = nil
        }
    }

    /// The panel is opening: surface any cached update now (first
    /// frame, before show — no shift), and poll if due. A poll that
    /// finishes while open won't touch the panel; its result waits for
    /// panelDidClose.
    func panelWillOpen() {
        panelIsOpen = true
        checkIfDue()
    }

    /// The panel closed: pick up anything the in-view poll cached, so
    /// the menubar dot reflects it and the next open shows the banner
    /// from the first frame.
    func panelDidClose() {
        panelIsOpen = false
        refreshAvailable()
    }

    /// Re-derive the notice from the cached latest version, then poll
    /// GitHub if a day has passed. Called at launch (panel closed) and,
    /// via panelWillOpen, whenever the panel opens.
    func checkIfDue() {
        guard enabled else {
            available = nil
            return
        }
        refreshAvailable()
        let last = defaults.double(forKey: lastCheckKey)
        if Date.timeIntervalSinceReferenceDate - last >= interval {
            Task { await poll() }
        }
    }

    /// Hide the notice for this version; a later release re-raises it.
    func dismiss() {
        guard let version = available?.version else { return }
        defaults.set(version, forKey: dismissedKey)
        refreshAvailable()
    }

    /// Set `available` from the cached latest version: shown when it
    /// beats the running build and hasn't been dismissed.
    private func refreshAvailable() {
        guard enabled,
            let latest = defaults.string(forKey: latestVersionKey),
            let urlString = defaults.string(forKey: latestURLKey),
            let url = URL(string: urlString),
            Version.isNewer(latest, than: Self.currentVersion),
            latest != defaults.string(forKey: dismissedKey)
        else {
            available = nil
            return
        }
        available = Update(version: latest, url: url)
    }

    private func poll() async {
        var request = URLRequest(url: latestReleaseAPI)
        // GitHub rejects API calls without a User-Agent; the JSON header
        // pins the response shape.
        request.setValue("promptu", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return }

        // tag_name is "v0.4.0"; drop the v for comparison and display.
        let version = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst()) : release.tag_name
        defaults.set(Date.timeIntervalSinceReferenceDate, forKey: lastCheckKey)
        defaults.set(version, forKey: latestVersionKey)
        defaults.set(release.html_url, forKey: latestURLKey)
        // Don't disturb an open panel; panelDidClose surfaces it later.
        if !panelIsOpen { refreshAvailable() }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    private static let currentVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
}
