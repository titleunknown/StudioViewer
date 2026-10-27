import Foundation
import Observation
import UserNotifications

/// "Check for Updates…": asks GitHub for the latest StudioViewer release and, if it's newer, offers the
/// download. Copied from PortScope's UpdateChecker. Updates replace the whole app, never its bundled
/// Python or cloudflared alone: those are signed and notarized as part of it. (A newer cloudflared
/// can be downloaded outside the app instead; see CloudflaredUpdate.)
@MainActor
@Observable
final class UpdateChecker {
    /// The public releases repo. While it doesn't exist (or is private) GitHub answers 404, which lands
    /// in the same "couldn't check right now" branch as being offline, so this is safe to ship before
    /// the repo goes public, and starts working the moment it does, with no code change.
    /// Releases are tagged with the version ("v1.0" or "1.0") and carry the notarized zip.
    static let repo = "titleunknown/StudioViewer"

    /// Where "Download…" sends the user to get the new version.
    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    static let shared = UpdateChecker()

    /// Off by default: StudioViewer makes no network request of its own accord for this unless asked to.
    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let lastAnnouncedKey = "lastAnnouncedUpdate"
    /// How often an automatic check may run.
    private static let autoInterval: TimeInterval = 24 * 3600

    private(set) var status: String?
    private(set) var checking = false
    /// True once a check found a newer release, so the window can offer the download.
    private(set) var updateAvailable = false

    @ObservationIgnored private var autoTimer: Timer?

    var lastChecked: Date? { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }

    /// Starts the once-a-day background check. Safe to call at launch: it does nothing unless the
    /// preference is on, and looks at the clock hourly so switching it on (or a Mac waking from
    /// sleep) is noticed without a relaunch.
    func startAutoChecks() {
        guard autoTimer == nil else { return }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
        checkIfDue()
    }

    private func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.autoInterval { return }
        check(automatic: true)
    }

    func check(automatic: Bool = false) {
        guard !checking else { return }
        checking = true
        if !automatic { status = "Checking…" }
        updateAvailable = false
        Task {
            defer { checking = false }
            do {
                let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                if Self.isNewer(latest, than: AppInfo.shortVersion) {
                    status = "Update available: \(latest)."
                    updateAvailable = true
                    // Say so once per version, not on every daily check.
                    if automatic, UserDefaults.standard.string(forKey: Self.lastAnnouncedKey) != latest {
                        UserDefaults.standard.set(latest, forKey: Self.lastAnnouncedKey)
                        announce(latest)
                    }
                } else {
                    status = "You're up to date (\(AppInfo.shortVersion))."
                }
            } catch {
                // An automatic check that can't connect stays quiet: offline is not news, and it
                // retries within the hour.
                if !automatic { status = "Couldn't check for updates right now." }
            }
        }
    }

    private func announce(_ latest: String) {
        let content = UNMutableNotificationContent()
        content.title = "StudioViewer \(latest) is available"
        content.body = "You have \(AppInfo.shortVersion). Open About StudioViewer to download it."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-\(latest)", content: content, trigger: nil))
    }

    /// Numeric dotted-version comparison ("1.2.0" > "1.1.9"). SemVer pre-release / build metadata is
    /// dropped before comparing, so "1.2.0-beta.1" counts as "1.2.0" and never reads as newer than it.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? version
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let lhs = index < a.count ? a[index] : 0
            let rhs = index < b.count ? b[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}

private nonisolated struct GitHubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}
