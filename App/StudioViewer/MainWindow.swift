import SwiftUI

extension View {
    /// A section's footer: left-aligned and full width. (A grouped Form on macOS lines footers up on
    /// the right, which reads oddly once they wrap.)
    func sectionFooter() -> some View {
        foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Runs a command for the viewer and shows its error, if any, in `message` (cleared as it starts).
func perform(into message: Binding<String?>, _ command: @escaping () async -> String?) {
    message.wrappedValue = nil
    Task { message.wrappedValue = await command() }
}

/// The window's panels, listed in the sidebar.
enum Panel: String, CaseIterable, Identifiable {
    case addresses, viewers, remote, ratings, settings, log, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .addresses: "Addresses"
        case .viewers: "Viewers"
        case .remote: "Remote Sharing"
        case .ratings: "Ratings & Tags"
        case .settings: "Settings"
        case .log: "Log"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .addresses: "network"
        case .viewers: "person.2"
        case .remote: "globe"
        case .ratings: "star"
        case .settings: "gearshape"
        case .log: "doc.text"
        case .about: "info.circle"
        }
    }
}

/// Which panel the window shows. Shared, so the app menu (About, Settings…) and the menu bar can
/// open the window on a particular panel.
@Observable
final class Navigation {
    var panel: Panel = Panel(rawValue: UserDefaults.standard.string(forKey: "panel") ?? "") ?? .addresses {
        didSet { UserDefaults.standard.set(panel.rawValue, forKey: "panel") }
    }
}

struct MainWindow: View {
    @Environment(Navigation.self) private var navigation
    @Environment(Tunnel.self) private var tunnel
    @Environment(Engine.self) private var engine

    private var connectedDevices: Int { engine.devices.filter { !$0.blocked && $0.left != true }.count }

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader()
            Divider()
            HStack(spacing: 0) {
                List(selection: selection) {
                    ForEach(Panel.allCases) { panel in
                        Label {
                            HStack {
                                Text(panel.title)
                                Spacer()
                                if panel == .viewers, connectedDevices > 0 {
                                    Text("\(connectedDevices)").foregroundStyle(.secondary).monospacedDigit()
                                }
                                if panel == .remote, let dot = remoteDot {
                                    Circle().fill(dot).frame(width: 7, height: 7)
                                        .accessibilityLabel("Remote sharing status")
                                }
                            }
                        } icon: {
                            Image(systemName: panel.symbol)
                        }
                        .tag(panel)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 660)
    }

    private var selection: Binding<Panel?> {
        Binding { navigation.panel } set: { if let panel = $0 { navigation.panel = panel } }
    }

    /// Remote sharing's status colour, while it's on.
    private var remoteDot: Color? {
        tunnel.state == .off ? nil : tunnel.state.color
    }

    @ViewBuilder private var detail: some View {
        switch navigation.panel {
        case .addresses: Form { AddressesSection() }.formStyle(.grouped)
        case .viewers: Form { ViewersSection() }.formStyle(.grouped)
        case .remote: Form { RemoteSection() }.formStyle(.grouped)
        case .ratings: Form { AccessSection() }.formStyle(.grouped)
        case .settings: SettingsView()
        case .log: LogView()
        case .about: ScrollView { AboutView().frame(maxWidth: .infinity) }
        }
    }
}

// MARK: - Status and Start/Stop

extension Engine.Phase {
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .waitingForCaptureOne: "Waiting for Capture One"
        case .live: "Live"
        case .captureOneLost: "Capture One isn't answering"
        case .stopping: "Stopping…"
        case .failed: "Stopped unexpectedly"
        }
    }

    var symbol: String {
        switch self {
        case .stopped: "eye.slash"
        case .starting, .waitingForCaptureOne, .stopping: "eye"
        case .live: "eye.fill"
        case .captureOneLost, .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .live: .green
        case .starting, .waitingForCaptureOne, .stopping: .orange
        case .captureOneLost, .failed: .red
        case .stopped: .secondary
        }
    }
}

extension Tunnel.State {
    /// Green while connected, orange while it connects or reconnects, red if it failed.
    var color: Color {
        switch self {
        case .connected: .green
        case .starting, .reconnecting: .orange
        case .failed: .red
        case .off: .secondary
        }
    }
}

struct StatusHeader: View {
    @Environment(Engine.self) private var engine
    @Environment(Navigation.self) private var navigation

    var body: some View {
        let phase = engine.phase
        HStack(spacing: 14) {
            Image(systemName: phase.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(phase.color)
                .frame(width: 48, height: 48)
                .background(phase.color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .live && !engine.session.isEmpty ? "Live · \(engine.session)" : phase.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if phase == .live, engine.viewers.total > 0 {
                    // Who's watching: opens the Viewers panel.
                    Button(detail(phase)) { navigation.panel = .viewers }
                        .buttonStyle(.link)
                        .help("See who's watching")
                } else {
                    Text(detail(phase))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Button {
                engine.isRunning ? engine.stop() : engine.start()
            } label: {
                Text(engine.isRunning ? "Stop" : "Start")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? .red : .accentColor)
            .controlSize(.large)
            .disabled(phase == .stopping)
            .keyboardShortcut(.return, modifiers: .command)
            .help(engine.isRunning ? "Stop the viewer (⌘↩)" : "Start the viewer (⌘↩)")
        }
        .padding(20)
    }

    private func detail(_ phase: Engine.Phase) -> String {
        switch phase {
        case .stopped: return "Start the viewer to share your Capture One session."
        case .starting: return "Looking for Capture One…"
        case .waitingForCaptureOne: return "Open your session in Capture One and turn on Live for Studio sharing."
        case .live: return Self.watching(engine.viewers)
        case .captureOneLost: return "Is it still open, with Live for Studio sharing? Viewers reconnect by themselves."
        case .stopping: return "Closing Capture One connections."
        case .failed(let reason): return reason
        }
    }

    static func watching(_ v: Viewers) -> String {
        let remote = v.remote > 0 ? " (\(v.remote) remote)" : ""
        switch v.total {
        case 0: return "No one is watching yet."
        case 1: return "1 browser watching" + remote
        default: return "\(v.total) browsers watching" + remote
        }
    }
}

// MARK: - Addresses

struct AddressesSection: View {
    @Environment(Engine.self) private var engine

    var body: some View {
        Section {
            if engine.urls != nil, engine.isRunning {
                ForEach(Address.list(engine.urls)) { address in
                    AddressRow(address: address) {
                        Windows.shared.showQR(address.url)
                    }
                }
            } else {
                Text("The addresses appear here once the viewer is running.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Addresses")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let moved = engine.portMoved {
                    Label(moved, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                Text(LaunchOptions.current.localOnly
                     ? "Only this Mac can open the viewer. Change it in Settings."
                     : "Phones, tablets and computers on the same network can open these. For a client screen, use the QR code's fullscreen option.")
                    .sectionFooter()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AddressRow: View {
    let address: Address
    let showQR: () -> Void
    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(address.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(address.url)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            Spacer()
            Button { Address.copy(address.url); flashCopied() } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy address")
            .accessibilityLabel("Copy \(address.label) address")
            Button(action: showQR) { Image(systemName: "qrcode") }
                .help("Show QR code")
                .accessibilityLabel("Show QR code for \(address.label)")
            Button { Address.open(address.url) } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Open in browser")
                .accessibilityLabel("Open \(address.label) address in browser")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }

    private func flashCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

// MARK: - Rating and tags

struct AccessSection: View {
    @Environment(Engine.self) private var engine
    @State private var mode: RatingMode = .view
    @State private var pin = ""
    @State private var tries = 5
    @State private var wait = 60
    @State private var message: String?
    @State private var confirmSignOut = false

    private static let waits = [(30, "30 seconds"), (60, "1 minute"), (300, "5 minutes"), (900, "15 minutes"), (3600, "1 hour")]

    var body: some View {
        Section {
            Picker("Other devices", selection: $mode) {
                ForEach(RatingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, new in modeChanged(new) }

            if mode == .pin {
                // A labelled row, so only the digits are monospaced, not the label.
                LabeledContent("PIN") {
                    HStack {
                        TextField("PIN", text: $pin, prompt: Text("4 to 8 digits"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.leading)
                            .frame(width: 130)
                            .onSubmit(savePIN)
                        Button("Save PIN", action: savePIN)
                            .disabled(!RatingMode.isValidPIN(pin) || (pin == engine.settings?.pin && engine.settings?.rating == .pin))
                    }
                }
                Stepper(value: $tries, in: 1...20) {
                    Text("Wrong tries allowed per device: \(tries)")
                }
                .onChange(of: tries) { saveLockout() }
                Picker("Then wait", selection: $wait) {
                    ForEach(Self.waits, id: \.0) { Text($0.1).tag($0.0) }
                }
                .onChange(of: wait) { saveLockout() }
            }

            HStack {
                if let message {
                    Text(message).foregroundStyle(.red)
                }
                Spacer()
                Button("Sign Out All Devices…", role: .destructive) { confirmSignOut = true }
            }
        } header: {
            Text("Rating & tags")
        } footer: {
            Text(footer).sectionFooter()
        }
        .disabled(engine.settings == nil || !engine.isRunning)
        .onAppear(perform: load)
        .onChange(of: engine.settings) { load() }
        .confirmationDialog("Sign out all devices?", isPresented: $confirmSignOut) {
            Button("Sign Out All Devices", role: .destructive) {
                perform(into: $message) { await engine.signOutAllDevices() }
            }
        } message: {
            Text("Every phone, tablet or computer that entered the PIN has to enter it again.")
        }
    }

    private var footer: String {
        if !engine.isRunning { return "This Mac can always rate and tag. Start the viewer to change what others can do." }
        switch mode {
        case .view: return "This Mac can always rate and tag. Others can look, zoom and filter."
        case .pin: return "Others rate and tag after entering the PIN once (remembered for 30 days). A new PIN signs out devices that used the old one."
        case .open: return "Everyone who opens the viewer can rate and tag."
        }
    }

    private func load() {
        guard let s = engine.settings else { return }
        mode = s.rating
        pin = s.pin
        tries = s.maxFails
        wait = Self.waits.contains { $0.0 == s.lockout } ? s.lockout : 60
    }

    private func modeChanged(_ new: RatingMode) {
        guard let s = engine.settings, new != s.rating else { return }
        // PIN mode needs a PIN first; with one already saved, switching is enough.
        if new == .pin && !RatingMode.isValidPIN(pin) { return }
        perform(into: $message) { await engine.setRating(new, pin: pin) }
    }

    private func savePIN() {
        guard RatingMode.isValidPIN(pin) else {
            message = "Use a PIN of 4 to 8 digits."
            return
        }
        perform(into: $message) { await engine.setRating(.pin, pin: pin) }
    }

    private func saveLockout() {
        guard let s = engine.settings, tries != s.maxFails || wait != s.lockout else { return }
        perform(into: $message) { await engine.setLockout(tries: tries, seconds: wait) }
    }
}

// MARK: - Log

struct LogView: View {
    @Environment(Engine.self) private var engine
    @Environment(Tunnel.self) private var tunnel

    /// The viewer's messages, then cloudflared's if remote sharing has run.
    private var text: String {
        engine.log.joined(separator: "\n")
            + (tunnel.log.isEmpty ? "" : "\n\n— Remote sharing (cloudflared) —\n" + tunnel.log.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .defaultScrollAnchor(.bottom)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            HStack {
                Text("Messages from the viewer and, when remote sharing has run, from cloudflared. Your tunnel token never appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Log") { Address.copy(text) }
            }
        }
        .padding(20)
    }
}
