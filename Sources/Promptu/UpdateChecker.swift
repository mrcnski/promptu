import Foundation
import PromptuCore

/// Polls the GitHub Releases API for a newer version and, when one is
/// found, surfaces it as `available` for the composer's notice row and
/// the menubar badge. The check is opt-out (it pings GitHub with the
/// user's IP), throttled to once a day, and silent on any failure —
/// offline or rate-limited means no notice, never an error.
///
/// The settings row reads `latestKnown` and `status` instead: it is a
/// status readout rather than a notification, so it reports a dismissed
/// version, says when a check is running or failed, and updates even
/// while the panel is open.
@MainActor
final class UpdateChecker: ObservableObject {
    /// A newer release than the running build.
    struct Update: Equatable {
        let version: String
        let url: URL
    }

    /// Where a check stands, for the settings row — the one place a
    /// check can be started by hand and so the one place a failure or
    /// an in-flight poll is worth reporting.
    enum Status: Equatable {
        case idle, checking, failed
    }

    @Published private(set) var available: Update?
    /// The newest known release with the dismissal ignored: dismissing
    /// the banner hides the nagging, not the fact, and the settings row
    /// should still report it.
    @Published private(set) var latestKnown: Update?
    @Published private(set) var status = Status.idle
    /// Whether the periodic check runs; off stops the GitHub pings.
    /// Published rather than read from UserDefaults on demand, so the
    /// settings rows render it right on their first frame.
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
        // Off clears both: refreshAvailable derives them through the
        // enabled guard.
        on ? checkIfDue() : refreshAvailable()
    }

    /// When the last successful check landed, nil until one has.
    var lastCheck: Date? {
        let stamp = defaults.double(forKey: lastCheckKey)
        return stamp == 0 ? nil : Date(timeIntervalSinceReferenceDate: stamp)
    }

    /// Check right now, ignoring the daily throttle: the settings row's
    /// "check now". A dismissed version stays dismissed — the row
    /// reports it either way, and re-raising the banner from a button
    /// press elsewhere would surprise.
    func checkNow() {
        guard enabled else { return }
        Task { await poll() }
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
        refreshAvailable()
        guard enabled else { return }
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

    /// Re-derive both published updates from the cache.
    private func refreshAvailable() {
        latestKnown = computeUpdate(ignoringDismissal: true)
        available = computeUpdate(ignoringDismissal: false)
    }

    /// The cached latest version when it beats the running build, else
    /// nil. `ignoringDismissal` is what separates the settings row from
    /// the banner.
    private func computeUpdate(ignoringDismissal: Bool) -> Update? {
        guard enabled,
            let latest = defaults.string(forKey: latestVersionKey),
            let urlString = defaults.string(forKey: latestURLKey),
            let url = URL(string: urlString),
            Version.isNewer(latest, than: Self.currentVersion),
            ignoringDismissal || latest != defaults.string(forKey: dismissedKey)
        else { return nil }
        return Update(version: latest, url: url)
    }

    /// Fetch the latest release and cache it. A second call while one is
    /// already in flight drops out: `lastCheckKey` is stamped only when a
    /// check succeeds, so opening, closing and reopening the panel inside
    /// a single request would otherwise clear the throttle again and fire
    /// a redundant GitHub ping. Setting `status` before the first `await`,
    /// on the main actor, is what makes the guard hold.
    private func poll() async {
        guard status != .checking else { return }
        status = .checking
        var request = URLRequest(url: latestReleaseAPI)
        // GitHub rejects API calls without a User-Agent; the JSON header
        // pins the response shape.
        request.setValue("promptu", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let release = try? JSONDecoder().decode(Release.self, from: data)
        else {
            status = .failed
            return
        }

        // tag_name is "v0.4.0"; drop the v for comparison and display.
        let version =
            release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst()) : release.tag_name
        defaults.set(Date.timeIntervalSinceReferenceDate, forKey: lastCheckKey)
        defaults.set(version, forKey: latestVersionKey)
        defaults.set(release.html_url, forKey: latestURLKey)
        status = .idle
        // The settings row updates either way: its text swaps in place,
        // where the banner appearing would resize the panel mid-view.
        latestKnown = computeUpdate(ignoringDismissal: true)
        // Don't disturb an open panel; panelDidClose surfaces it later.
        if !panelIsOpen { available = computeUpdate(ignoringDismissal: false) }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    /// The running build's version, as shown in settings. Absent
    /// outside an app bundle (a `swift run` from the checkout), where
    /// "dev" parses as 0 and so counts as older than every release.
    static let currentVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}
