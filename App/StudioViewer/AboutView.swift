import SwiftUI

/// Version details, for the About panel (and anyone asking for support).
enum AppInfo {
    static var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
    static var versionLine: String { "Version \(shortVersion) (\(build))" }

    /// "Python 3.13.16 · cloudflared 2026.10.2", from the bundled helpers' VERSION files (cloudflared: the copy in use).
    static var components: String {
        var parts: [String] = []
        if let v = bundledVersion("python"), let m = v.range(of: #"cpython-([0-9.]+)"#, options: .regularExpression) {
            parts.append("Python " + v[m].dropFirst("cpython-".count))
        } else {
            parts.append("Python: this Mac's own")
        }
        // The version in use: a downloaded update (CloudflaredUpdate) may be newer than the bundled copy.
        if let v = CloudflaredUpdate.shared.current ?? bundledVersion("cloudflared") {
            parts.append("cloudflared " + v)
        }
        return parts.joined(separator: " · ")
    }

    private static func bundledVersion(_ helper: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appending(path: "\(helper)/VERSION"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// About StudioViewer: icon, version, Faini Made, the privacy policy, support and the licences of what's bundled.
/// Laid out like PortScope's About tab.
struct AboutView: View {
    @State private var updateChecker = UpdateChecker.shared
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates = false

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("StudioViewer").font(.title2.bold())
            Text(AppInfo.versionLine)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("See your Capture One shoot live in any web browser, in the studio or anywhere.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link("by Faini Made", destination: URL(string: "https://fainimade.com")!)
                .help("fainimade.com")
            Link("Privacy Policy", destination: URL(string: "https://fainimade.com/privacy")!)
                .font(.subheadline)
                .help("fainimade.com/privacy")

            // StudioViewer is free: this is the way to support it (the README has the same link).
            Text("StudioViewer is free. If it earns its keep on your shoots:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Link(destination: URL(string: "https://buymeacoffee.com/fainimade")!) {
                Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.867, blue: 0), in: Capsule())  // Buy Me a Coffee's yellow
            }
            .buttonStyle(.plain)
            .help("buymeacoffee.com/fainimade")

            Divider().padding(.vertical, 4)

            VStack(spacing: 6) {
                Button {
                    updateChecker.check()
                } label: {
                    if updateChecker.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check for Updates\u{2026}")
                    }
                }
                if let status = updateChecker.status {
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                }
                if updateChecker.updateAvailable {
                    Button("Download\u{2026}") { NSWorkspace.shared.open(UpdateChecker.releasesURL) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)
                    .help("Asks GitHub once a day while StudioViewer is running. Nothing about your Mac is sent.")
                    .onChange(of: autoCheckUpdates) { _, on in
                        if on { updateChecker.check(automatic: true) }
                    }
            }

            Divider().padding(.vertical, 4)

            Text("Includes \(AppInfo.components)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            // The bundled programs' licences require their notices to travel with every copy of the app.
            Button("Acknowledgments\u{2026}") { Windows.shared.showAcknowledgments() }
                .buttonStyle(.link)
                .font(.subheadline)
            Text("Not endorsed by or affiliated with Capture One A/S.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("© 2026 Faini Made Inc. All Rights Reserved")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// The open-source software bundled in the app, with the licence texts shipped alongside it.
/// A window of its own: licence text needs more room than the About panel has.
struct AcknowledgmentsView: View {
    private struct Notice: Identifiable {
        let name, by, licence, url: String
        let file: String  // the licence text, relative to Contents/Resources
        let extra: String?
        var id: String { name }
    }

    private let notices = [
        Notice(name: "cloudflared", by: "Cloudflare, Inc.", licence: "Apache License 2.0",
               url: "https://github.com/cloudflare/cloudflared", file: "cloudflared/LICENSE",
               extra: "Runs remote sharing. Bundled unmodified, re-signed for this app."),
        Notice(name: "Python", by: "Python Software Foundation", licence: "PSF License Agreement",
               url: "https://www.python.org", file: "python/lib/python3.13/LICENSE.txt",
               extra: "Runs the viewer. Built by the python-build-standalone project (Astral), which also includes "
                   + "OpenSSL, SQLite, libffi, zlib, bzip2, XZ and mpdecimal under their own licences."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Acknowledgments").font(.title2.bold())
            Text("StudioViewer includes the following open-source software. Their licences are reproduced here, as they require.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(notices) { notice in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(notice.name).font(.headline)
                                Text("\(notice.by) · \(notice.licence)").foregroundStyle(.secondary)
                                Spacer()
                                Link("Website", destination: URL(string: notice.url)!).font(.subheadline)
                            }
                            if let extra = notice.extra {
                                Text(extra).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(licenceText(notice.file))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Link("Licences of the libraries inside Python's build",
                         destination: URL(string: "https://gregoryszorc.com/docs/python-build-standalone/main/running.html#licensing")!)
                        .font(.subheadline)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 400, idealHeight: 620)
    }

    private func licenceText(_ file: String) -> String {
        guard let url = Bundle.main.resourceURL?.appending(path: file),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Not bundled in this build (development builds may use this Mac's own copy)."
        }
        return text
    }
}

/// The app menu's "About StudioViewer" and "Settings…": both open the main window on their panel,
/// in place of the standard About panel and a separate Settings window.
struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About StudioViewer") { Windows.shared.showMain(panel: .about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { Windows.shared.showMain(panel: .settings) }
                .keyboardShortcut(",")
        }
    }
}
