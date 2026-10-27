import Foundation

/// Which Python runs the viewer: the one bundled in the app (App/scripts/fetch-python.sh), or else
/// this Mac's own python3, which is fine for development.
enum Python {
    static func locate() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appending(path: "python/bin/python3"),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"] where fm.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        // /usr/bin/python3 is only a stub that offers to install the Command Line Tools, unless they
        // (or Xcode) are installed.
        let real = ["/Library/Developer/CommandLineTools/usr/bin/python3",
                    "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"]
        if real.contains(where: fm.isExecutableFile(atPath:)) {
            return URL(filePath: "/usr/bin/python3")
        }
        return nil
    }
}

enum Paths {
    /// ~/Library/Application Support/StudioViewer: settings.json (access mode, PINs, codes).
    /// Not next to the script, which is inside the signed app.
    nonisolated static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "StudioViewer", directoryHint: .isDirectory)
    }
    static var settings: URL { folder.appending(path: "settings.json") }

    /// cloudflared's own HOME and (empty) config, so it never reads ~/.cloudflared.
    nonisolated static var cloudflaredHome: URL { folder.appending(path: "cloudflared", directoryHint: .isDirectory) }
    static var cloudflaredConfig: URL { cloudflaredHome.appending(path: "config.yml") }
    private static var cloudflaredPID: URL { cloudflaredHome.appending(path: "cloudflared.pid") }

    static func prepareCloudflared() throws {
        try FileManager.default.createDirectory(at: cloudflaredHome, withIntermediateDirectories: true)
        // A config of its own, so cloudflared never reads ~/.cloudflared. Not just a comment: an
        // "empty" config makes cloudflared log an error.
        try Data("# StudioViewer's own cloudflared config.\nno-autoupdate: true\n".utf8).write(to: cloudflaredConfig)
    }

    /// Remembered so a cloudflared left behind by a crash can be stopped at the next launch.
    static func saveCloudflaredPID(_ pid: Int32?) {
        if let pid { try? Data(String(pid).utf8).write(to: cloudflaredPID) } else { try? FileManager.default.removeItem(at: cloudflaredPID) }
    }

    static func savedCloudflaredPID() -> Int32? {
        (try? String(contentsOf: cloudflaredPID, encoding: .utf8)).flatMap { Int32($0) }
    }
}

/// UserDefaults keys. Defaults are registered in AppDelegate.
enum Prefs {
    static let port = "port"
    static let localOnly = "localOnly"
    static let startOnLaunch = "startOnLaunch"
    static let showWindowAtLaunch = "showWindowAtLaunch"
    static let alwaysShowInDock = "alwaysShowInDock"
    static let notify = "notify"
    static let remoteOn = "remoteOn"
    static let remoteMode = "remoteMode"
    static let publicAddress = "publicAddress"
    /// Fixed, because the Cloudflare tunnel is set up to reach exactly this port. Outside the
    /// 8787-8796 range the viewer may move its main port to.
    static let tunnelPort = "tunnelPort"
    /// The ports the viewer and the tunnel can use: lower ones are reserved by macOS.
    static let usablePorts = 1024...65535
    /// Hidden (no UI): use this Capture One address instead of finding it. See Engine.start().
    static let captureOneAddress = "captureOneAddress"
    /// The saved tunnel token's ID (not secret); the token itself is in the Keychain.
    static let tunnelID = "tunnelID"

    static let defaults: [String: Any] = [
        port: 8787, localOnly: false, startOnLaunch: true, showWindowAtLaunch: true,
        alwaysShowInDock: false, notify: true,
        remoteOn: false, remoteMode: Tunnel.Mode.domain.rawValue, publicAddress: "", tunnelPort: 8797,
    ]
}
