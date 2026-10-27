import SwiftUI

/// "Remote sharing" in the main window: the on/off switch, how to connect (your domain or a
/// temporary link), the tunnel token and public address, and the viewing code people need.
struct RemoteSection: View {
    @Environment(Engine.self) private var engine
    @Environment(Tunnel.self) private var tunnel
    @AppStorage(Prefs.remoteOn) private var remoteOn = false
    @AppStorage(Prefs.remoteMode) private var modeRaw = Tunnel.Mode.domain.rawValue
    @AppStorage(Prefs.publicAddress) private var publicAddress = ""
    @AppStorage(Prefs.tunnelPort) private var tunnelPort = 8797
    @State private var tokenDraft = ""
    @State private var code = ""
    @State private var requireCode = true
    @State private var message: String?
    @State private var showSetup = false
    @State private var confirmOpen = false
    @State private var cloudflared = CloudflaredUpdate.shared

    private var mode: Tunnel.Mode { Tunnel.Mode(rawValue: modeRaw) ?? .domain }

    var body: some View {
        Section {
            Toggle(isOn: $remoteOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share outside the studio")
                    Text(status).font(.caption).foregroundStyle(tunnel.state.color)
                }
            }
            .disabled(!remoteOn && tunnel.missing != nil)
            .onChange(of: remoteOn) { tunnel.sync() }

            if case .failed = tunnel.state, remoteOn {
                HStack {
                    Spacer()
                    Button("Try Again") { tunnel.retry() }
                }
            }

            if tunnel.isConnected, let url = tunnel.publicURL {
                AddressRow(address: Address(label: "Anywhere, with the viewing code", url: url)) {
                    Windows.shared.showQR(url)
                }
            }

            Picker("Connect with", selection: $modeRaw) {
                ForEach(Tunnel.Mode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .disabled(remoteOn)

            if mode == .domain {
                tokenRow
                TextField("Public address", text: $publicAddress, prompt: Text("https://studio.example.com"))
                    .disabled(remoteOn)
                DisclosureGroup("How to set up your own address", isExpanded: $showSetup) { setupSteps }
            }

            Toggle("Ask for a viewing code", isOn: $requireCode)
                .onChange(of: requireCode) { _, on in requireCodeChanged(on) }
            if requireCode {
                // A labelled row, so only the digits are monospaced, not the label.
                LabeledContent("Viewing code") {
                    HStack {
                        TextField("Viewing code", text: $code, prompt: Text("6 to 12 digits"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.leading)
                            .frame(width: 130)
                            .onSubmit(saveCode)
                        Button("New Code") { code = Self.randomCode() }
                        Button("Save", action: saveCode)
                            .disabled(!Self.isValidCode(code) || code == engine.settings?.remoteCode)
                    }
                }
            }

            if let message {
                Text(message).foregroundStyle(.red)
            }

            cloudflaredRow

            HStack {
                Text("New to this? The guide covers everything from a Cloudflare account onwards.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Setup Guide…") { Tunnel.openSetupGuide() }
            }
        } header: {
            Text("Remote sharing")
        } footer: {
            Text(footer).sectionFooter()
        }
        .onAppear {
            load()
            cloudflared.checkIfDue()
        }
        .onChange(of: engine.settings) { load() }
        .confirmationDialog("Let anyone with the address watch?", isPresented: $confirmOpen) {
            Button("Turn Off the Viewing Code", role: .destructive) {
                perform(into: $message) { await engine.setRemoteViewing(requireCode: false, code: engine.settings?.remoteCode ?? "") }
            }
            Button("Cancel", role: .cancel) { requireCode = true }
        } message: {
            Text("Only do this if Cloudflare Access already protects the address, for example with email codes.")
        }
    }

    // MARK: Parts

    @ViewBuilder private var tokenRow: some View {
        if let id = tunnel.savedTunnelID {
            LabeledContent("Tunnel token") {
                HStack {
                    Text("In your Keychain · tunnel \(id.prefix(8))…").foregroundStyle(.secondary)
                    Button("Remove") { _ = tunnel.setToken(nil) }
                        .disabled(remoteOn)
                }
            }
        } else {
            HStack {
                SecureField("Tunnel token", text: $tokenDraft, prompt: Text("Paste the token or the install command"))
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .disabled(tokenDraft.isEmpty)
            }
        }
    }

    /// The cloudflared version in use, and a way to update it between app releases.
    private var cloudflaredRow: some View {
        LabeledContent {
            HStack {
                if cloudflared.busy { ProgressView().controlSize(.small) }
                if cloudflared.usingDownloaded, !cloudflared.updateAvailable {
                    Button("Use Built-In") {
                        cloudflared.useBuiltIn()
                        tunnel.restart()
                    }
                    .disabled(cloudflared.busy)
                }
                if cloudflared.updateAvailable, let latest = cloudflared.latest {
                    Button("Update to \(latest)") {
                        cloudflared.update { tunnel.restart() }
                    }
                    .disabled(cloudflared.busy)
                } else {
                    Button("Check Now") { cloudflared.check() }
                        .disabled(cloudflared.busy)
                }
            }
        } label: {
            Text("cloudflared \(cloudflared.current ?? "not found")")
            Text(cloudflaredDetail)
                .foregroundStyle(cloudflared.failed ? .red : cloudflared.updateAvailable ? .orange : .secondary)
        }
    }

    private var cloudflaredDetail: String {
        if let status = cloudflared.status { return status }
        var parts: [String] = []
        if let running = tunnel.runningVersion, tunnel.isRunning, running != cloudflared.current {
            parts.append("Running \(running)")
        }
        if cloudflared.updateAvailable, let latest = cloudflared.latest {
            parts.append(tunnel.isRunning ? "\(latest) is available. Sharing reconnects for a moment while it updates."
                                          : "\(latest) is available.")
        } else if cloudflared.latest != nil {
            parts.append("Up to date.")
        }
        if parts.isEmpty { parts.append("Cloudflare's tunnel program, which connects this Mac to Cloudflare.") }
        if cloudflared.usingDownloaded { parts.append("Downloaded update; the app's built-in copy is older.") }
        return parts.joined(separator: " ")
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
                You need a free Cloudflare account and a domain on Cloudflare. The Setup Guide walks \
                through all of it, including signing up and moving or buying a domain.

                1. In the Cloudflare dashboard, open **Networking › Tunnels**, select **Create a tunnel**, \
                name it (for example "StudioViewer") and select **Create Tunnel**.
                2. Choose **macOS**, copy the install command shown (don't run it) and paste it into \
                **Tunnel token** above. Save.
                3. Make sure a viewing code is saved, switch on **Share outside the studio**, and once the \
                dashboard shows the tunnel connected, select **Continue**.
                4. Open the tunnel's **Routes** tab › **Add route** › **Published application**. Pick a \
                subdomain (such as "view") and your domain, and enter this **Service URL**:
                """)
            HStack {
                Text(verbatim: "http://localhost:\(tunnelPort)")  // verbatim: not turned into a link
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Button("Copy") { Address.copy("http://localhost:\(tunnelPort)") }
            }
            .padding(.leading, 18)
            Text("5. Select **Add route**, then type the full address (for example view.yourstudio.com) into **Public address** above.")
            HStack {
                Button("Open the Setup Guide") { Tunnel.openSetupGuide() }
                Button("Create a Cloudflare Account") { Address.open("https://dash.cloudflare.com/sign-up") }
                Button("Open the Dashboard") { Address.open("https://dash.cloudflare.com/") }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        switch tunnel.state {
        case .off:
            if let missing = tunnel.missing { return missing }
            return "Off"
        case .starting: return "Connecting to Cloudflare…"
        case .connected where tunnel.publicURL == nil:
            return "Connected. Enter the public address to get its link and QR code."
        case .connected:
            let remote = engine.viewers.remote
            return remote == 0 ? "On. No one is watching remotely yet." : "On · \(remote) watching remotely"
        case .reconnecting: return "Connection to Cloudflare lost; reconnecting…"
        case .failed(let reason): return reason
        }
    }

    private var footer: String {
        switch mode {
        case .domain:
            "People open your own address from anywhere and enter the viewing code. Your Mac stays hidden behind Cloudflare; nothing is opened on your router."
        case .quick:
            "A random trycloudflare.com address, new each time sharing starts. No Cloudflare account needed. Give people the address and the viewing code."
        }
    }

    // MARK: Actions

    private func load() {
        guard let s = engine.settings else { return }
        requireCode = s.remoteView != "open"
        if code.isEmpty || code == s.remoteCode { code = s.remoteCode }
        if requireCode, code.isEmpty { code = Self.randomCode() }
    }

    private func saveToken() {
        message = tunnel.setToken(tokenDraft)
        if message == nil { tokenDraft = "" }
    }

    private func saveCode() {
        guard Self.isValidCode(code) else {
            message = "Use a viewing code of 6 to 12 digits."
            return
        }
        perform(into: $message) { await engine.setRemoteViewing(requireCode: true, code: code) }
    }

    private func requireCodeChanged(_ on: Bool) {
        guard let s = engine.settings, on != (s.remoteView != "open") else { return }
        if on {
            if !Self.isValidCode(code) { code = Self.randomCode() }
            saveCode()
        } else {
            confirmOpen = true
        }
    }

    static func isValidCode(_ code: String) -> Bool {
        (6...12).contains(code.count) && code.allSatisfy(\.isASCIIDigit)
    }

    static func randomCode() -> String {
        String((0..<6).map { _ in "0123456789".randomElement()! })
    }
}
