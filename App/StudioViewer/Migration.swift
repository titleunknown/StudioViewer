import Foundation

/// StudioViewer was called LfS Viewer (bundle ID Faini-Made.LfS-Viewer) until October 2026. On the
/// first launch under the new name, the old preferences and Application Support folder (settings.json
/// with the PIN, viewing code and removed devices; cloudflared's home) are copied over, so nothing has
/// to be set up again. Copied, not moved, so the old app still works if someone goes back to it.
///
/// The tunnel token is copied later, from the Keychain, when sharing first starts (see Keychain):
/// reading it may make macOS ask, which must never hold up the launch.
enum Migration {
    nonisolated static let oldBundleID = "Faini-Made.LfS-Viewer"
    private static let doneKey = "migratedFromLfSViewer"

    /// Run before anything reads preferences.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // Only into a fresh install: never over settings made under the new name.
        let newDomain = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        if newDomain.isEmpty, let old = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in old { defaults.set(value, forKey: key) }
        }

        let fm = FileManager.default
        let oldFolder = URL.applicationSupportDirectory.appending(path: "LfS Viewer", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: oldFolder.path), !fm.fileExists(atPath: Paths.folder.path) else { return }
        do {
            try fm.copyItem(at: oldFolder, to: Paths.folder)
            // That PID is the old app's cloudflared, which may still be running: not ours to stop.
            Paths.saveCloudflaredPID(nil)
        } catch {
            try? fm.removeItem(at: Paths.folder)  // a partial copy would read as set up
        }
    }
}
