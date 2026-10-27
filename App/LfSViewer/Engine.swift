import Foundation
import Observation

/// Runs the viewer itself (lfs_viewer.py, bundled in the app) as a child process in --control mode,
/// and mirrors what it reports. The protocol is documented at the top of lfs_viewer.py ("Control"):
/// events arrive on its stdout as lines starting with "@lfs ", commands go to its stdin as JSON lines.
@Observable
final class Engine {
    enum Phase: Equatable {
        case stopped, starting, waitingForCaptureOne, live, captureOneLost, stopping
        case failed(String)
    }

    /// Something worth a notification (see Notifier).
    enum Alert {
        case captureOneLost, captureOneBack, guessing
        case crashed(String), error(String)
        case tunnelDropped, tunnelBack, tunnelFailed(String)  // remote sharing (see Tunnel)
    }

    private(set) var isRunning = false
    private(set) var session = ""
    private(set) var urls: ViewerURLs?
    private(set) var viewers = Viewers()
    /// Connected and removed devices, for the Viewers panel (see Devices in lfs_viewer.py).
    private(set) var devices: [Device] = []
    private(set) var settings: AccessSettings?
    private(set) var log: [String] = []
    /// What the running viewer was started with, to tell when Settings need a restart.
    private(set) var startedWith: LaunchOptions?
    /// The viewer's tunnel port while it's open (remote sharing on).
    private(set) var tunnelPort: Int?
    /// The port the viewer is on, and the one it was asked for: they differ when that one was in use.
    private(set) var port: Int?
    private(set) var requestedPort: Int?
    /// "Port 8787 was in use, so the viewer is on 8788.", or nil.
    var portMoved: String? {
        guard let port, let requestedPort, port != requestedPort else { return nil }
        return "Port \(requestedPort) was in use, so the viewer is on \(port). Addresses and QR codes with \(requestedPort) won't work; choose a free port in Settings to keep them the same."
    }
    private(set) var isListening = false
    private var c1State = ""
    private var stopping = false
    private var failure: String?
    private var lastError: String?

    var onAlert: (Alert) -> Void = { _ in }
    /// Called when the viewer starts listening or stops, so remote sharing can follow it.
    var onRunningChange: () -> Void = {}

    private var process: Process?
    private var input: FileHandle?
    private var reader: PipeLines?  // the viewer's output, line by line
    private var run = 0  // which start() the process belongs to
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<String?, Never>] = [:]
    private var restartAfterStop = false

    var phase: Phase {
        if !isRunning { return failure.map(Phase.failed) ?? .stopped }
        if stopping { return .stopping }
        switch c1State {
        case "lost": return .captureOneLost
        case "waiting": return .waitingForCaptureOne
        case "connected" where isListening: return .live
        default: return .starting
        }
    }

    // MARK: Starting and stopping

    func start() {
        guard process == nil else { return }
        failure = nil
        lastError = nil
        guard let python = Python.locate() else {
            failure = "Python 3 isn't installed. Install it from python.org, then start again."
            onAlert(.crashed(failure!))
            return
        }
        guard let script = Bundle.main.url(forResource: "lfs_viewer", withExtension: "py") else {
            failure = "The app is missing lfs_viewer.py. Reinstall LfS Viewer."
            return
        }
        let options = LaunchOptions.current
        let p = Process()
        p.executableURL = python
        // -I: ignore the user's Python setup; -u: unbuffered output; -B: never write .pyc into the app.
        p.arguments = ["-I", "-u", "-B", script.path, "--control", "--no-open",
                       "--settings", Paths.settings.path, "--port", String(options.port)]
            + (options.localOnly ? ["--local"] : [])
        // Hidden, for troubleshooting and tests: a Capture One address to use instead of finding it.
        //     defaults write Faini-Made.LfS-Viewer captureOneAddress 127.0.0.1:50163
        if let c1 = UserDefaults.standard.string(forKey: Prefs.captureOneAddress), !c1.isEmpty {
            p.arguments! += ["--c1", c1]
            append("Using Capture One at \(c1) (captureOneAddress setting)")
        }
        let output = Pipe(), commands = Pipe()
        p.standardOutput = output
        p.standardError = output
        p.standardInput = commands

        run += 1
        let thisRun = run
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self.ended(run: thisRun, status: status) } }
        }
        do {
            try p.run()
        } catch {
            failure = "The viewer couldn't start: \(error.localizedDescription)"
            onAlert(.crashed(failure!))
            return
        }
        process = p
        input = commands.fileHandleForWriting
        isRunning = true
        stopping = false
        c1State = ""
        isListening = false
        startedWith = options
        append("Started with \(python.path)")
        reader = PipeLines(output.fileHandleForReading) { line in
            MainActor.assumeIsolated {
                guard self.run == thisRun else { return }
                self.handle(line)
            }
        }
    }

    /// Asks the viewer to stop (it closes its Capture One sessions first). If it hasn't gone after
    /// a few seconds, it's terminated.
    func stop() {
        guard let process, !stopping else { return }
        stopping = true
        write(["cmd": "stop"])
        let thisRun = run
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard self.run == thisRun, self.process === process, process.isRunning else { return }
            process.terminate()
        }
    }

    func restart() {
        guard isRunning else { start(); return }
        restartAfterStop = true
        stop()
    }

    private func ended(run thisRun: Int, status: Int32) {
        guard thisRun == run else { return }
        let expected = stopping
        process = nil
        input = nil
        isRunning = false
        stopping = false
        isListening = false
        tunnelPort = nil
        port = nil
        requestedPort = nil
        c1State = ""
        viewers = Viewers()
        devices = []
        for (_, waiting) in pending { waiting.resume(returning: "The viewer stopped.") }
        pending = [:]
        onRunningChange()
        if !expected {
            // The reason, if it gave one: an error event, or the last line of a Python traceback
            // ("OSError: ..."). Ordinary log lines aren't reasons.
            let traceback = log.suffix(5).last { $0.range(of: #"^\w*(Error|Exception)\b"#, options: .regularExpression) != nil }
            failure = lastError ?? traceback ?? "The viewer stopped unexpectedly. The log may say why."
            onAlert(.crashed(failure!))
        }
        append(expected ? "Stopped." : "Stopped unexpectedly (exit code \(status)).")
        if restartAfterStop {
            restartAfterStop = false
            start()
        }
    }

    // MARK: Commands

    /// Sends a command and waits for its reply. Returns the error message, or nil if it worked.
    @discardableResult
    func send(_ command: [String: Any]) async -> String? {
        guard input != nil else { return "Start the viewer first." }
        nextID += 1
        let id = nextID
        var message = command
        message["id"] = id
        guard write(message) else { return "The viewer isn't answering." }
        return await withCheckedContinuation { pending[id] = $0 }
    }

    @discardableResult
    private func write(_ message: [String: Any]) -> Bool {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: message) else { return false }
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)  // SIGPIPE is ignored (AppDelegate), so a dead pipe throws
            return true
        } catch {
            return false
        }
    }

    func setRating(_ mode: RatingMode, pin: String) async -> String? {
        await send(["cmd": "access", "mode": mode.rawValue, "pin": pin])
    }

    func setLockout(tries: Int, seconds: Int) async -> String? {
        await send(["cmd": "lockout", "maxFails": tries, "seconds": seconds])
    }

    /// How visitors' pages name you: "Enter the viewing code the digi-tech gave you."
    func setOperator(_ name: String) async -> String? {
        await send(["cmd": "wording", "operator": name])
    }

    func signOutAllDevices() async -> String? {
        await send(["cmd": "signout"])
    }

    /// Removes a device: its page is cut off and it stays out until unblocked.
    func removeDevice(_ id: String) async -> String? {
        await send(["cmd": "block", "device": id])
    }

    func unblockDevice(_ id: String) async -> String? {
        await send(["cmd": "unblock", "device": id])
    }

    /// Stops (or allows again) rating and tagging on one device, whatever the rating mode.
    func setDeviceRating(_ id: String, allow: Bool) async -> String? {
        await send(["cmd": "rating", "device": id, "allow": allow])
    }

    /// Opens the viewer's tunnel port (nil closes it). Viewers on the network aren't disturbed.
    func openTunnelPort(_ port: Int?) async -> String? {
        await send(["cmd": "tunnel", "port": port.map { $0 as Any } ?? NSNull()])
    }

    /// Whether remote visitors need the viewing code (open: only when Cloudflare Access guards the address).
    func setRemoteViewing(requireCode: Bool, code: String) async -> String? {
        await send(["cmd": "remote", "view": requireCode ? "code" : "open", "code": code])
    }

    // MARK: Events

    private static let decoder = JSONDecoder()

    private func handle(_ line: String) {
        // One decoding pass per line, straight into the event's fields.
        guard line.hasPrefix("@lfs "),
              let event = try? Self.decoder.decode(ViewerEvent.self, from: Data(line.utf8.dropFirst(5)))
        else {
            append(line)
            return
        }
        switch event.event {
        case "settings":
            if let settings = event.settings, settings != self.settings { self.settings = settings }
        case "c1":
            let state = event.state ?? ""
            if let name = event.session, !name.isEmpty { session = name }
            if state == "lost", c1State == "connected" { onAlert(.captureOneLost) }
            if state == "connected", c1State == "lost" { onAlert(.captureOneBack) }
            c1State = state
        case "listening":
            urls = event.urls
            port = event.port
            requestedPort = event.requestedPort
            tunnelPort = event.tunnelPort
            isListening = true
            onRunningChange()
        case "tunnel":
            tunnelPort = event.port
        case "addresses":
            if let urls = event.urls, urls != self.urls { self.urls = urls }
        case "viewers":
            let viewers = Viewers(total: event.total ?? 0, remote: event.remote ?? 0)
            if viewers != self.viewers { self.viewers = viewers }
        case "devices":
            // Only on a real change, so the window isn't redrawn for nothing.
            if let devices = event.devices, devices != self.devices { self.devices = devices }
        case "guessing":
            onAlert(.guessing)
        case "error":
            let message = event.message ?? "Something went wrong."
            lastError = message
            append(message)
            onAlert(.error(message))
        case "reply":
            if let id = event.id, let waiting = pending.removeValue(forKey: id) {
                waiting.resume(returning: event.ok == true ? nil : (event.error ?? "That didn't work."))
            }
        default:
            break  // "status" and "stopped": nothing to add
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

// MARK: - What the viewer reports

/// One "@lfs {...}" line from the viewer: every event's fields, each there only for its own events
/// (see "Control" at the top of lfs_viewer.py).
private struct ViewerEvent: Decodable {
    var event: String
    var state: String?
    var session: String?
    var urls: ViewerURLs?
    var port: Int?
    var requestedPort: Int?
    var tunnelPort: Int?
    var total: Int?
    var remote: Int?
    var devices: [Device]?
    var settings: AccessSettings?
    var message: String?
    var id: Int?
    var ok: Bool?
    var error: String?
}

struct AccessSettings: Codable, Equatable {
    var mode: String
    var pin: String
    var maxFails: Int
    var lockout: Int
    var remoteView: String
    var remoteCode: String
    /// How visitors' pages name whoever runs the viewer ("the photographer", "the digi-tech"...).
    var `operator`: String?

    var rating: RatingMode { RatingMode(rawValue: mode) ?? .view }
}

/// What other devices may do (the Mac running the viewer can always rate).
enum RatingMode: String, CaseIterable, Identifiable {
    case view, pin, open
    var id: String { rawValue }
    var title: String {
        switch self {
        case .view: "View only"
        case .pin: "PIN to rate"
        case .open: "Anyone can rate"
        }
    }

    static func isValidPIN(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy(\.isASCIIDigit)
    }
}

struct ViewerURLs: Codable, Equatable {
    struct Network: Codable, Equatable, Hashable {
        var interface: String
        var url: String
    }
    var local: String
    var network: [Network]
    var bonjour: String?
}

/// A browser watching (or removed from) the viewer, as lfs_viewer.py reports it.
struct Device: Codable, Identifiable, Equatable {
    enum Place: String, Codable {
        case thisMac = "this-mac", network, remote
    }
    var id: String
    var name: String
    var place: Place
    var ip: String
    var email: String
    var country: String?
    var city: String?
    var region: String?
    var lat: Double?
    var lon: Double?
    var folder: String?
    var photo: String?
    var ratings: Int?
    var tags: Int?
    var canRate: Bool?
    var unlocked: Bool?
    var ratingBlocked: Bool?
    var since: Double?
    var lastSeen: Double?
    var bytes: Int?
    var blocked: Bool
    var left: Bool?
    var blockedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, place = "where", ip, email, country, city, region, lat, lon, folder, photo, ratings, tags,
             canRate, unlocked, ratingBlocked, since, lastSeen, bytes, blocked, left, blockedAt
    }

    /// "Austin, Texas, United States", from what Cloudflare sends (remote visitors only).
    var location: String? {
        let countryName = country.flatMap { $0.isEmpty ? nil : Locale.current.localizedString(forRegionCode: $0) ?? $0 }
        let parts = [city, region, countryName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Apple Maps at the visitor's rough location: Cloudflare's coordinates if it sent them, else the place name.
    var mapURL: URL? {
        guard let location else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "q", value: location)]
        if let lat, let lon {
            c.queryItems! += [URLQueryItem(name: "ll", value: "\(lat),\(lon)"), URLQueryItem(name: "z", value: "10")]
        }
        return c.url
    }

    /// What's known about a public IP address, on ipinfo.io (opened only when asked).
    var ipInfoURL: URL? {
        place == .remote && !ip.isEmpty ? URL(string: "https://ipinfo.io/" + ip) : nil
    }
}

struct Viewers: Equatable {
    var total = 0
    var remote = 0
}

/// The options that only take effect when the viewer starts.
struct LaunchOptions: Equatable {
    var port: Int
    var localOnly: Bool

    static var current: LaunchOptions {
        let d = UserDefaults.standard
        return LaunchOptions(port: d.integer(forKey: Prefs.port), localOnly: d.bool(forKey: Prefs.localOnly))
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
