import CryptoKit
import Foundation
import Observation
import Security

/// Keeps cloudflared current between app releases. The copy bundled in the app can't be replaced
/// (that would break the app's signature), so a newer release is downloaded into Application Support
/// and checked the same way App/scripts/fetch-cloudflared.sh checks the bundled one: the SHA-256 in
/// Cloudflare's release notes, and Cloudflare's own Developer ID signature. Tunnel.binary() then uses
/// whichever of the two is newer, so a later app release with a newer bundled copy takes over again.
@MainActor
@Observable
final class CloudflaredUpdate {
    static let shared = CloudflaredUpdate()

    private nonisolated static let repo = "cloudflare/cloudflared"
    private nonisolated static let asset = "cloudflared-darwin-arm64.tgz"
    /// Cloudflare Inc.'s Developer ID (team 68WVV388M8): the requirement its releases are signed to.
    private nonisolated static let requirement = #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "68WVV388M8""#
    /// Checking when the Remote Sharing panel opens, at most this often (GitHub allows 60 an hour).
    private static let checkInterval: TimeInterval = 3600

    /// The cloudflared to run: the newer of the bundled and downloaded copies.
    private(set) var binary: URL?
    /// Its version.
    private(set) var current: String?
    /// The latest release, once a check has found it.
    private(set) var latest: String?
    private(set) var busy = false
    private(set) var status: String?
    private(set) var failed = false
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var choosing: Task<Void, Never>?
    @ObservationIgnored private var choice = 0  // which refresh() the latest choice belongs to

    private init() {
        // Until refresh() has chosen: whichever copy exists, so the app can tell there is one.
        let fm = FileManager.default
        binary = Tunnel.bundledBinary() ?? (fm.isExecutableFile(atPath: Self.downloaded.path) ? Self.downloaded : nil)
        refresh()
    }

    var updateAvailable: Bool {
        guard let latest, let current else { return false }
        return UpdateChecker.isNewer(latest, than: current)
    }

    /// True when the downloaded copy is the one in use.
    var usingDownloaded: Bool { binary == Self.downloaded }

    /// Picks the copy to run, off the main thread: it runs each copy for its version and checks the
    /// downloaded one's signature. Done at launch and after an update, not on every use.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        choice += 1
        let thisChoice = choice
        let task = Task {
            let (binary, version) = await Task.detached { Self.choose() }.value
            guard thisChoice == choice else { return }
            self.binary = binary
            current = version
        }
        choosing = task
        return task
    }

    /// Waits for refresh() to finish, so sharing starts on the copy it chose.
    func chosen() async {
        await choosing?.value
    }

    func checkIfDue() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        check()
    }

    func check() {
        guard !busy else { return }
        busy = true
        failed = false
        status = "Checking…"
        Task {
            defer { busy = false }
            do {
                latest = try await Self.release().version
                lastCheck = Date()
                status = nil
            } catch {
                fail("Couldn't check for a newer cloudflared right now.")
            }
        }
    }

    /// Downloads, checks and installs the latest release. Calls `installed` (on the main actor) once
    /// it's in place, so remote sharing can restart on it.
    func update(installed: @escaping () -> Void) {
        guard !busy else { return }
        busy = true
        failed = false
        status = "Downloading…"
        Task {
            defer { busy = false }
            do {
                let release = try await Self.release()
                latest = release.version
                let (data, response) = try await URLSession.shared.data(from: release.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw Problem(message: "Couldn't download cloudflared \(release.version).")
                }
                let version = try await Task.detached { try Self.install(release, data: data) }.value
                await refresh().value
                status = "Updated to \(version)."
                installed()
            } catch let error as Problem {
                fail(error.message)
            } catch {
                fail("Couldn't update cloudflared: \(error.localizedDescription)")
            }
        }
    }

    /// Goes back to the copy built into the app.
    func useBuiltIn() {
        try? FileManager.default.removeItem(at: Self.downloaded.deletingLastPathComponent())
        refresh()
        status = nil
    }

    private func fail(_ message: String) {
        status = message
        failed = true
    }

    // MARK: Finding, checking and installing

    /// ~/Library/Application Support/LfS Viewer/cloudflared/bin/cloudflared
    nonisolated static var downloaded: URL {
        Paths.cloudflaredHome.appending(path: "bin/cloudflared")
    }

    /// The newer of the bundled and downloaded copies, with its version. A downloaded copy is only
    /// used while its signature holds; once it isn't newer (an app update bundled one as new) or
    /// isn't valid, it would never be used again, so it's deleted.
    private nonisolated static func choose() -> (URL?, String?) {
        let bundled = Tunnel.bundledBinary()
        let bundledVersion = bundled.flatMap(version(of:))
        guard FileManager.default.fileExists(atPath: downloaded.path) else { return (bundled, bundledVersion) }
        if isSignedByCloudflare(downloaded), let version = version(of: downloaded),
           bundledVersion.map({ UpdateChecker.isNewer(version, than: $0) }) ?? true {
            return (downloaded, version)
        }
        try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent())
        return (bundled, bundledVersion)
    }

    nonisolated struct Problem: Error { let message: String }

    private nonisolated struct Release: Sendable {
        let version: String
        let url: URL
        let sha256: String
    }

    private nonisolated static func release() async throws -> Release {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let link = assets.first(where: { $0["name"] as? String == asset })?["browser_download_url"] as? String,
              let url = URL(string: link) else { throw Problem(message: "Couldn't read cloudflared's latest release.") }
        // The release notes list "cloudflared-darwin-arm64.tgz: <sha256>", the checksum of the
        // cloudflared program inside the .tgz (not of the .tgz itself).
        let body = json["body"] as? String ?? ""
        let pattern = NSRegularExpression.escapedPattern(for: asset) + #":\s*([0-9a-f]{64})"#
        guard let match = body.range(of: pattern, options: .regularExpression) else {
            throw Problem(message: "cloudflared \(tag)'s release notes give no checksum, so it wasn't installed.")
        }
        return Release(version: tag, url: url, sha256: String(body[match].suffix(64)))
    }

    /// Unpacks and checks a downloaded release, then moves it into place. Returns its version.
    private nonisolated static func install(_ release: Release, data: Data) throws -> String {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "cloudflared-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let tgz = work.appending(path: asset)
        try data.write(to: tgz)
        _ = try run(URL(filePath: "/usr/bin/tar"), ["-xzf", tgz.path, "-C", work.path])
        let binary = work.appending(path: "cloudflared")

        guard let unpacked = try? Data(contentsOf: binary), sha256(unpacked) == release.sha256 else {
            throw Problem(message: "The download didn't match the checksum Cloudflare published, so it wasn't installed.")
        }
        guard isSignedByCloudflare(binary) else {
            throw Problem(message: "The download isn't signed by Cloudflare, so it wasn't installed.")
        }
        guard let version = version(of: binary) else {
            throw Problem(message: "The downloaded cloudflared didn't run, so it wasn't installed.")
        }

        let folder = downloaded.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Replaced in one step, so a cloudflared already running from here keeps its file.
        _ = try fm.replaceItemAt(downloaded, withItemAt: binary)
        return version
    }

    /// Whether the file carries Cloudflare Inc.'s valid Developer ID signature.
    nonisolated static func isSignedByCloudflare(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), req) == errSecSuccess
    }

    /// "2026.10.2", from "cloudflared version 2026.10.2 (built …)".
    nonisolated static func version(of binary: URL) -> String? {
        guard let output = try? run(binary, ["--version"]),
              let range = output.range(of: #"version ([0-9][0-9.]*)"#, options: .regularExpression) else { return nil }
        return String(output[range].dropFirst("version ".count))
    }

    private nonisolated static func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        // Its own HOME, as when sharing, so it never reads ~/.cloudflared.
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = Paths.cloudflaredHome.path
        p.environment = environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Problem(message: "\(executable.lastPathComponent) failed.") }
        return String(decoding: output, as: UTF8.self)
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
