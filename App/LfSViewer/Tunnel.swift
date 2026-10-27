import AppKit
import Foundation
import Observation
import Security

/// Remote sharing: runs cloudflared (bundled in the app) so people outside the studio can open the
/// viewer, through the viewer's tunnel port (see "Remote" at the top of lfs_viewer.py), where they
/// need the viewing code first.
///
/// Two ways to connect:
///  - Your own domain: a Cloudflare Tunnel made in the Cloudflare dashboard, whose public hostname
///    points at http://localhost:<tunnel port>. The app keeps only the tunnel's token, in the
///    Keychain, and hands it to cloudflared in its environment (never on the command line).
///  - A temporary link: a random https://….trycloudflare.com address, no account needed.
///
/// cloudflared runs isolated: its own empty config file and its own HOME, so it never reads (or
/// disturbs) a ~/.cloudflared set up for something else, such as PIX.
@Observable
final class Tunnel {
    enum Mode: String, CaseIterable, Identifiable {
        case domain, quick
        var id: String { rawValue }
        var title: String {
            switch self {
            case .domain: "Your domain"
            case .quick: "Temporary link"
            }
        }
    }

    enum State: Equatable {
        case off, starting, reconnecting
        case connected(Int)  // cloudflared's live connections to Cloudflare (normally 4)
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var quickURL: String?
    private(set) var log: [String] = []
    /// The cloudflared version this run started with.
    private(set) var runningVersion: String?
    /// The saved token's tunnel ID, to show that one is saved. Only this (not secret) is kept in
    /// preferences; the token itself is read from the Keychain only when sharing starts, so a
    /// Keychain prompt (after an app update, say) can never hold up the app's launch.
    private(set) var savedTunnelID = UserDefaults.standard.string(forKey: Prefs.tunnelID)

    weak var engine: Engine?
    var onAlert: (Engine.Alert) -> Void = { _ in }

    private var process: Process?
    private var reader: PipeLines?  // cloudflared's output, line by line
    private var run = 0
    private var stopping = false
    private var restarting = false
    private var poll: Task<Void, Never>?
    private var connections = 0
    private var droppedAt: Date?
    private var startedAt = Date()
    private var toldDropped = false
    private var lastError: String?
    private static let dropGrace: TimeInterval = 15
    /// cloudflared retries forever (a wrong token included), so give up after this long without a connection.
    private static let connectTimeout: TimeInterval = 30

    var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: Prefs.remoteMode) ?? "") ?? .domain }
    var isRunning: Bool { process != nil }
    var isConnected: Bool { if case .connected = state { true } else { false } }

    /// The address to give people, once there is one.
    var publicURL: String? {
        switch mode {
        case .quick: return quickURL
        case .domain:
            let address = UserDefaults.standard.string(forKey: Prefs.publicAddress) ?? ""
            return Self.normalized(address)
        }
    }

    /// What's still needed before sharing can start, or nil if it can.
    var missing: String? {
        guard Self.binary() != nil else { return "cloudflared isn't in the app. Run App/scripts/fetch-cloudflared.sh." }
        guard let engine, engine.isRunning, engine.isListening else { return "Start the viewer first." }
        let port = UserDefaults.standard.integer(forKey: Prefs.tunnelPort)
        guard Prefs.usablePorts.contains(port), port != engine.port else {
            return "Choose another tunnel port in Settings."
        }
        guard let s = engine.settings, s.remoteView == "open" || !s.remoteCode.isEmpty else {
            return "Set a viewing code first."
        }
        // The public address isn't needed to connect: Cloudflare's setup asks for the tunnel to connect
        // before the address (route) is made. It's only needed to show the link.
        if mode == .domain, savedTunnelID == nil { return "Add your tunnel's token first." }
        return nil
    }

    // MARK: Turning it on and off

    /// Runs cloudflared when sharing is switched on and the viewer is running; stops it otherwise.
    func sync() {
        let wanted = UserDefaults.standard.bool(forKey: Prefs.remoteOn) && engine?.isListening == true
        if wanted, process == nil, missing == nil {
            start()
        } else if !wanted, process != nil || state != .off {
            stop()
        }
    }

    /// After a failure: forget it and try again.
    func retry() {
        if case .failed = state { state = .off }
        sync()
    }

    private func start() {
        guard let engine else { return }
        stopping = false
        state = .starting
        quickURL = nil
        lastError = nil
        connections = 0
        startedAt = Date()
        droppedAt = nil
        toldDropped = false
        run += 1
        let thisRun = run
        let port = UserDefaults.standard.integer(forKey: Prefs.tunnelPort)
        let mode = mode
        Task {
            // Off the main thread: macOS may ask before releasing a Keychain item.
            let token = mode == .domain ? await Task.detached { Keychain.tunnelToken }.value : nil
            guard run == thisRun, !stopping else { return }
            if mode == .domain, token == nil {
                fail("The tunnel token couldn't be read from the Keychain. Add it again.")
                return
            }
            // The viewer opens its tunnel port first, so cloudflared has somewhere to send visitors.
            if let error = await engine.openTunnelPort(port) {
                guard run == thisRun else { return }
                fail(error)
                return
            }
            // The copy to run, once CloudflaredUpdate has chosen (at launch, or after an update).
            await CloudflaredUpdate.shared.chosen()
            guard run == thisRun, !stopping else { return }
            guard let cloudflared = Self.binary() else {
                fail("cloudflared isn't in the app. Run App/scripts/fetch-cloudflared.sh.")
                _ = await engine.openTunnelPort(nil)
                return
            }
            launch(cloudflared, port: port, token: token, run: thisRun)
        }
    }

    private func launch(_ cloudflared: URL, port: Int, token: String?, run thisRun: Int) {
        let metrics = FreePort.find() ?? 20241
        let p = Process()
        p.executableURL = cloudflared
        runningVersion = CloudflaredUpdate.shared.current
        var arguments = ["tunnel", "--config", Paths.cloudflaredConfig.path, "--no-autoupdate",
                         "--grace-period", "2s", "--metrics", "127.0.0.1:\(metrics)"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = Paths.cloudflaredHome.path
        switch mode {
        case .quick:
            arguments += ["--url", "http://localhost:\(port)"]
        case .domain:
            arguments += ["run"]
            environment["TUNNEL_TOKEN"] = token
        }
        p.arguments = arguments
        p.environment = environment
        let output = Pipe()
        p.standardOutput = output
        p.standardError = output
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self.ended(run: thisRun, status: status) } }
        }
        do {
            try Paths.prepareCloudflared()
            try p.run()
        } catch {
            fail("cloudflared couldn't start: \(error.localizedDescription)")
            return
        }
        process = p
        Paths.saveCloudflaredPID(p.processIdentifier)
        append("Started cloudflared \(runningVersion ?? "") (\(mode.title.lowercased())) for http://localhost:\(port)")
        reader = PipeLines(output.fileHandleForReading) { line in
            MainActor.assumeIsolated {
                guard self.run == thisRun else { return }
                self.handle(line)
            }
        }
        poll = Task { await watch(metrics: metrics, run: thisRun) }
    }

    func stop() {
        stopping = true
        restarting = false
        poll?.cancel()
        if let process, process.isRunning {
            process.terminate()  // ended() then marks it off
        } else {
            process = nil
            state = .off
        }
        Task { _ = await engine?.openTunnelPort(nil) }
    }

    /// Starts cloudflared again (after an update, to run the new version). The viewer's tunnel port
    /// stays open, so visitors only wait for the reconnect.
    func restart() {
        guard let process, process.isRunning else { return }
        restarting = true
        stopping = true
        poll?.cancel()
        process.terminate()  // ended() then starts it again
    }

    /// When the app quits: don't leave cloudflared running without it.
    func stopNow() {
        stopping = true
        restarting = false
        process?.terminate()
        Paths.saveCloudflaredPID(nil)
    }

    private func ended(run thisRun: Int, status: Int32) {
        guard thisRun == run else { return }
        process = nil
        poll?.cancel()
        Paths.saveCloudflaredPID(nil)
        if restarting {
            restarting = false
            state = .off
            append("Restarting cloudflared…")
            sync()
            return
        }
        if stopping {
            if case .failed = state {} else { state = .off }  // a give-up keeps its reason on screen
            append("cloudflared stopped.")
            return
        }
        fail(lastError ?? "cloudflared stopped (exit code \(status)).")
        Task { _ = await engine?.openTunnelPort(nil) }
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
        append(reason)
        onAlert(.tunnelFailed(reason))
    }

    // MARK: Watching it

    private func handle(_ line: String) {
        append(line)
        if quickURL == nil, let range = line.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
            quickURL = String(line[range])
        }
        // cloudflared logs as "2026-10-20T21:30:00Z ERR message error=\"detail\" key=value";
        // keep the latest error's detail as the likely reason.
        if line.contains(" ERR ") {
            let message = line.components(separatedBy: " ERR ").last ?? line
            if let r = message.range(of: #"error="[^"]+""#, options: .regularExpression) {
                lastError = String(message[r].dropFirst(7).dropLast())
            } else {
                lastError = message.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    /// Asks cloudflared's metrics server every few seconds how many connections to Cloudflare are up
    /// (/ready), and for a temporary link, its address (/quicktunnel), which is sturdier than its log.
    private func watch(metrics: Int, run thisRun: Int) async {
        let base = "http://127.0.0.1:\(metrics)"
        var lastProblem: String?
        while !Task.isCancelled, run == thisRun {
            try? await Task.sleep(for: .seconds(3))
            var ready = 0
            do {
                let json = try await Self.json(base + "/ready")
                ready = json["readyConnections"] as? Int ?? 0
                if mode == .quick, quickURL == nil, let host = try? await Self.json(base + "/quicktunnel")["hostname"] as? String,
                   !host.isEmpty {
                    quickURL = "https://" + host
                    append("Temporary link: \(quickURL!)")
                }
                lastProblem = nil
            } catch {
                // Normal for a moment while cloudflared starts; logged once so a lasting problem shows.
                let problem = "Waiting for cloudflared's status (\(error.localizedDescription))"
                if problem != lastProblem { append(problem) }
                lastProblem = problem
            }
            guard !Task.isCancelled, run == thisRun, process != nil else { return }
            update(ready: ready)
        }
    }

    private static func json(_ url: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func update(ready: Int) {
        if ready != connections {
            append(ready == 0 ? "No connections to Cloudflare." : "Connections to Cloudflare: \(ready)")
            connections = ready
        }
        // A temporary link isn't usable until its address is known.
        if ready > 0, mode == .domain || quickURL != nil {
            if toldDropped { onAlert(.tunnelBack) }
            state = .connected(ready)
            droppedAt = nil
            toldDropped = false
        } else if case .connected = state {
            state = .reconnecting
            droppedAt = Date()
        } else if state == .starting, Date().timeIntervalSince(startedAt) > Self.connectTimeout {
            giveUp(Self.explain(lastError))
        } else if state == .reconnecting, let since = droppedAt, !toldDropped,
                  Date().timeIntervalSince(since) > Self.dropGrace {
            toldDropped = true
            onAlert(.tunnelDropped)
        }
    }

    /// Stops a cloudflared that can't connect, and says why.
    private func giveUp(_ reason: String) {
        stopping = true
        poll?.cancel()
        fail(reason)
        process?.terminate()
        Task { _ = await engine?.openTunnelPort(nil) }
    }

    /// cloudflared's error, in words a photographer can act on.
    static func explain(_ error: String?) -> String {
        guard let error else { return "Couldn't connect to Cloudflare within 30 seconds." }
        let e = error.lowercased()
        if e.contains("failed to get tunnel") || e.contains("unauthorized") || e.contains("token") {
            return "Cloudflare doesn't recognise this tunnel. Check it still exists in the dashboard, or paste its token again."
        }
        if e.contains("no such host") || e.contains("dial") || e.contains("timeout") || e.contains("unreachable") {
            return "Can't reach Cloudflare. Check this Mac's internet connection."
        }
        return "Couldn't connect to Cloudflare: \(error)"
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    // MARK: The token

    /// Saves a pasted token (or the whole install command it came in). Returns an error message.
    func setToken(_ pasted: String?) -> String? {
        guard let pasted, !pasted.isEmpty else {
            Keychain.saveTunnelToken(nil)
            savedTunnelID = nil
            UserDefaults.standard.removeObject(forKey: Prefs.tunnelID)
            return nil
        }
        guard let parsed = TunnelToken(pasted) else {
            return "That doesn't look like a tunnel token. Copy the install command from the Cloudflare dashboard and paste it here."
        }
        guard Keychain.saveTunnelToken(parsed.raw) else {
            return "The token couldn't be saved in your Keychain. Try again, or check Keychain Access."
        }
        savedTunnelID = parsed.tunnelID
        UserDefaults.standard.set(parsed.tunnelID, forKey: Prefs.tunnelID)
        return nil
    }

    // MARK: Helpers

    /// Opens the setup guide (remote-setup.html, bundled) in the browser, with this Mac's tunnel
    /// port filled in. A browser may drop "?port=" from a file link, so a filled-in copy is opened.
    static func openSetupGuide() {
        guard let bundled = Bundle.main.url(forResource: "remote-setup", withExtension: "html"),
              var html = try? String(contentsOf: bundled, encoding: .utf8) else { return }
        let port = UserDefaults.standard.integer(forKey: Prefs.tunnelPort)
        html = html.replacingOccurrences(of: "8797", with: String(port))
        let copy = Paths.folder.appending(path: "Remote Sharing Setup.html")
        do {
            try FileManager.default.createDirectory(at: Paths.folder, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: copy)
            NSWorkspace.shared.open(copy)
        } catch {
            NSWorkspace.shared.open(bundled)
        }
    }

    /// The cloudflared to run: the bundled one, or a newer one downloaded by CloudflaredUpdate.
    static func binary() -> URL? { CloudflaredUpdate.shared.binary }

    nonisolated static func bundledBinary() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appending(path: "cloudflared/cloudflared"),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared"]
            .first(where: fm.isExecutableFile(atPath:)).map { URL(filePath: $0) }
    }

    /// "studio.example.com" -> "https://studio.example.com"; nil if it isn't a host name.
    static func normalized(_ address: String) -> String? {
        var a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return nil }
        if !a.contains("://") { a = "https://" + a }
        while a.hasSuffix("/") { a.removeLast() }
        guard let host = URL(string: a)?.host(), host.contains(".") else { return nil }
        return a
    }

    /// cloudflared left running by a previous run of the app that crashed: stop it.
    static func stopLeftover() {
        guard let pid = Paths.savedCloudflaredPID() else { return }
        defer { Paths.saveCloudflaredPID(nil) }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              String(cString: buffer).hasSuffix("/cloudflared") else { return }
        kill(pid, SIGTERM)
    }
}

/// A Cloudflare Tunnel token: base64 JSON {"a": account tag, "t": tunnel id, "s": secret}.
nonisolated struct TunnelToken {
    let raw: String
    let tunnelID: String

    /// Accepts the token itself, or text containing it (such as "sudo cloudflared service install eyJ…").
    init?(_ text: String) {
        guard let range = text.range(of: #"eyJ[A-Za-z0-9+/_=-]{40,}"#, options: .regularExpression) else { return nil }
        let candidate = String(text[range])
        var b64 = candidate.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tunnel = json["t"] as? String, json["s"] != nil else { return nil }
        raw = candidate
        tunnelID = tunnel
    }
}

/// The tunnel token, kept in the login Keychain.
nonisolated enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Faini-Made.LfS-Viewer",
        kSecAttrAccount as String: "cloudflare-tunnel-token",
    ]

    static var tunnelToken: String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the saved token (nil removes it). Returns whether the Keychain took it.
    @discardableResult
    static func saveTunnelToken(_ token: String?) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard let token else { return true }
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrLabel as String] = "LfS Viewer: Cloudflare tunnel token"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// A free TCP port on 127.0.0.1, for cloudflared's metrics (its /ready endpoint).
nonisolated enum FreePort {
    static func find() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0
            }
        }
        return bound ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }
}
