import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @AppStorage(Prefs.startOnLaunch) private var startOnLaunch = true
    @AppStorage(Prefs.showWindowAtLaunch) private var showWindowAtLaunch = true
    @AppStorage(Prefs.alwaysShowInDock) private var alwaysShowInDock = false
    @AppStorage(Prefs.port) private var port = 8787
    @AppStorage(Prefs.localOnly) private var localOnly = false
    @AppStorage(Prefs.notify) private var notify = true
    @AppStorage(Prefs.tunnelPort) private var tunnelPort = 8797
    @AppStorage(Prefs.remoteOn) private var remoteOn = false
    @State private var loginItem = SMAppService.mainApp.status
    @State private var draftPort = 8787
    @State private var portProblem: String?
    @State private var operatorName = ""
    @State private var wordingMessage: String?
    @State private var wordingSaved: String?  // shown after a save, until the field is edited again
    private static let operatorChoices = ["the photographer", "the digi-tech", "the operator", "the studio", "the admin"]

    var body: some View {
        Form {
            Section("When StudioViewer opens") {
                Toggle("Start the viewer", isOn: $startOnLaunch)
                Toggle("Show the window", isOn: $showWindowAtLaunch)
                Toggle("Open StudioViewer at login", isOn: loginBinding)
                if loginItem == .requiresApproval {
                    HStack {
                        Text("Allow it in System Settings › General › Login Items.")
                            .foregroundStyle(.secondary)
                        Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Always show in the Dock", isOn: $alwaysShowInDock)
                    .onChange(of: alwaysShowInDock) { DockIcon.update() }
            }

            Section {
                LabeledContent("Port") {
                    HStack {
                        TextField("Port", value: $draftPort, format: .number.grouping(.never))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 90)
                            .onSubmit(usePort)
                            .onChange(of: draftPort) { portProblem = nil }
                        Button("Use Port", action: usePort)
                            .disabled(draftPort == port)
                    }
                }
                if let portProblem {
                    Text(portProblem).foregroundStyle(.red)
                } else if let moved = engine.portMoved {
                    Label(moved, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Toggle("Only this Mac can open the viewer", isOn: $localOnly)
                if let started = engine.startedWith, engine.isRunning,
                   started != LaunchOptions(port: port, localOnly: localOnly) {
                    HStack {
                        Text("Restart the viewer to use these.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Viewer") { engine.restart() }
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text("The address other devices open, http://…:\(String(port)). Change it if something else on this Mac uses that port, or your network blocks it. If it's taken, the viewer uses the next free one and says so here.")
                    .sectionFooter()
            }

            Section {
                TextField("Tunnel port", value: $tunnelPort, format: .number.grouping(.never))
                    .disabled(remoteOn)
                if !Prefs.usablePorts.contains(tunnelPort) {
                    Text("Use a port from 1024 to 65535. Lower ones are reserved by macOS.").foregroundStyle(.red)
                } else if tunnelPort == port || tunnelPort == engine.port {
                    Text("The tunnel port can't be the same as the viewer's port.").foregroundStyle(.red)
                }
            } header: {
                Text("Remote sharing")
            } footer: {
                Text(remoteOn
                     ? "Turn off remote sharing to change the port."
                     : "Your Cloudflare tunnel's public hostname must point at http://localhost:\(String(tunnelPort)). The address of the remote viewer doesn't change.")
                    .sectionFooter()
            }

            Section {
                // A labelled row of its own (not a bare HStack), so each control keeps its own name.
                LabeledContent("Visitors see you as") {
                    HStack {
                        TextField("Visitors see you as", text: $operatorName, prompt: Text("the photographer"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)  // a Form right-aligns field text otherwise
                            .frame(minWidth: 150)
                            .onSubmit(saveOperator)
                        // Choosing only fills in the field: Save (or Return) saves it, like typing.
                        Menu("Choose") {
                            ForEach(Self.operatorChoices, id: \.self) { choice in
                                Button(choice) { operatorName = choice }
                            }
                        }
                        .fixedSize()
                        Button("Save", action: saveOperator)
                            .disabled(operatorName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || operatorName == engine.settings?.operator)
                    }
                }
                .disabled(!engine.isRunning)
                .onChange(of: operatorName) { _, name in
                    if name != wordingSaved { wordingSaved = nil }
                }
                if let wordingMessage {
                    Text(wordingMessage).foregroundStyle(.red)
                } else if let wordingSaved {
                    Label("Saved. Visitors' pages now say \u{201C}Enter the viewing code \(wordingSaved) gave you.\u{201D}",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Visitors' pages")
            } footer: {
                Text(engine.isRunning
                     ? "For example: \u{201C}Enter the viewing code \(operatorName.isEmpty ? "the photographer" : operatorName) gave you.\u{201D} Also used when a device is removed. Use any name, such as \u{201C}the digi-tech\u{201D} or \u{201C}Studio 4\u{201D}."
                     : "Start the viewer to change this.")
                    .sectionFooter()
            }

            Section {
                Toggle("Notify me when something goes wrong", isOn: $notify)
                    .onChange(of: notify) { _, on in if on { Notifier.askPermission() } }
            } header: {
                Text("Notifications")
            } footer: {
                Text("When Capture One stops answering for more than a few seconds, or the viewer stops unexpectedly.")
                    .sectionFooter()
            }

            Section("Files") {
                LabeledContent("Python") {
                    Text(Python.locate()?.path(percentEncoded: false) ?? "Not found")
                        .textSelection(.enabled)
                }
                LabeledContent("cloudflared") {
                    Text(Tunnel.binary()?.path(percentEncoded: false) ?? "Not found")
                        .textSelection(.enabled)
                }
                LabeledContent("Settings") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.settings])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: Paths.settings.path))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            draftPort = port
            loginItem = SMAppService.mainApp.status
            operatorName = engine.settings?.operator ?? "the photographer"
        }
        .onChange(of: engine.settings?.operator) { _, saved in
            if let saved { operatorName = saved }
        }
    }

    /// Checks the port, saves it and restarts the viewer on it (pages reconnect at the new address).
    private func usePort() {
        portProblem = nil
        guard Prefs.usablePorts.contains(draftPort) else {
            portProblem = "Use a port from 1024 to 65535. Lower ones are reserved by macOS."
            return
        }
        guard draftPort != tunnelPort else {
            portProblem = "\(draftPort) is the tunnel port (Remote sharing). Choose another."
            return
        }
        guard draftPort != port else { return }  // nothing changed: don't drop everyone for a restart
        port = draftPort
        if engine.isRunning { engine.restart() }
    }

    private func saveOperator() {
        let name = operatorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        wordingMessage = nil
        wordingSaved = nil
        Task {
            if let error = await engine.setOperator(name) {
                wordingMessage = error
            } else {
                // The viewer tidies spaces; show the wording as saved.
                wordingSaved = engine.settings?.operator ?? name
                operatorName = wordingSaved ?? name
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding {
            loginItem == .enabled || loginItem == .requiresApproval
        } set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSSound.beep()
            }
            loginItem = SMAppService.mainApp.status
        }
    }
}
