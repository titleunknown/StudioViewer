import AppKit
import Observation
import SwiftUI

/// The menu bar icon and its menu, in the style of Tailscale's: switch rows at the top for the
/// viewer and for remote sharing, then a few plain items. Built in AppKit, because a SwiftUI menu
/// bar menu turns every toggle into a checkmark and can't show custom rows. The switch rows are
/// SwiftUI views hosted in menu items, so they update live while the menu is open.
///
///     [LfS Viewer                       (on)]   Live · 4 watching · LfS Viewer - Demo
///     [Share Outside the Studio         (on)]   view.fainimade.com · 2 remote
///     Open Viewer in Browser             ⌘O
///     Addresses                           ›
///     Open LfS Viewer Window
///     Quit LfS Viewer                    ⌘Q
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let engine: Engine
    private let tunnel: Tunnel

    init(engine: Engine, tunnel: Tunnel) {
        self.engine = engine
        self.tunnel = tunnel
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        watchIcon()
    }

    // MARK: The icon

    /// Redraws the icon now, and again whenever what it shows changes.
    private func watchIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.watchIcon() } }
        }
    }

    private func updateIcon() {
        // Remote sharing failing is a problem too, even while the viewer itself is live.
        let symbol: String = switch tunnel.state {
        case .failed, .reconnecting: "exclamationmark.triangle.fill"
        default: engine.phase.symbol
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LfS Viewer: \(engine.phase.title)")
        image?.isTemplate = true
        item.button?.image = image
    }

    // MARK: The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(hosted(ViewerSwitchRow(engine: engine)))
        menu.addItem(hosted(SharingSwitchRow(engine: engine, tunnel: tunnel)))
        menu.addItem(.separator())
        menu.addItem(openItem)
        menu.addItem(addressesItem)
        menu.addItem(.separator())
        menu.addItem(ActionItem("Open LfS Viewer Window") { Windows.shared.showMain() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit LfS Viewer", key: "q") { NSApp.terminate(nil) })
    }

    // The switch rows update themselves; these two follow the viewer while the menu is open,
    // so switching it off there doesn't leave them pointing at a stopped viewer.
    private lazy var openItem = ActionItem("Open Viewer in Browser", key: "o") { [weak self] in
        if let self, engine.isRunning, let urls = engine.urls { Address.open(urls.local) }
    }
    private let addressesItem = NSMenuItem(title: "Addresses", action: nil, keyEquivalent: "")
    /// Bumped on every open and close, so a watch left over from an earlier opening stops.
    private var opening = 0
    private var menuOpen = false

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        opening += 1
        watchItems(opening)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        opening += 1
    }

    private func watchItems(_ id: Int) {
        guard menuOpen, id == opening else { return }
        withObservationTracking {
            updateItems()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.watchItems(id) } }
        }
    }

    private func updateItems() {
        let urls = engine.isRunning ? engine.urls : nil
        openItem.isEnabled = urls != nil
        let list = urls.map(shareable) ?? []
        addressesItem.isEnabled = !list.isEmpty
        guard !list.isEmpty else {
            addressesItem.submenu = nil
            return
        }
        let sub = NSMenu()
        for address in list {
            let entry = NSMenuItem(title: address.title, action: nil, keyEquivalent: "")
            let actions = NSMenu()
            actions.addItem(ActionItem("Copy Address") { Address.copy(address.url) })
            actions.addItem(ActionItem("Show QR Code") { Windows.shared.showQR(address.url) })
            actions.addItem(ActionItem("Open in Browser") { Address.open(address.url) })
            entry.submenu = actions
            sub.addItem(entry)
        }
        addressesItem.submenu = sub
    }

    private func hosted(_ view: some View) -> NSMenuItem {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }

    /// The network addresses, then the remote one when sharing is connected, each with a short label:
    /// "Wi-Fi: 192.168.8.165:8787", "Remote: view.fainimade.com".
    private func shareable(_ urls: ViewerURLs) -> [(title: String, url: String)] {
        var list = Address.shareable(urls).map { (title: "\(Self.shortLabel($0.label)): \(Self.hostPart($0.url))", url: $0.url) }
        if tunnel.isConnected, let url = tunnel.publicURL {
            list.append((title: "Remote: \(Self.hostPart(url))", url: url))
        }
        return list
    }

    /// "USB 10/100/1G/2.5G LAN (en15)" -> "Ethernet"; "Wi-Fi (en0)" -> "Wi-Fi".
    private static func shortLabel(_ label: String) -> String {
        let name = label.replacingOccurrences(of: #"\s*\(\w+\)$"#, with: "", options: .regularExpression)
        if name.localizedCaseInsensitiveContains("Wi-Fi") { return "Wi-Fi" }
        if name.localizedCaseInsensitiveContains("Thunderbolt") { return "Thunderbolt" }
        if name.localizedCaseInsensitiveContains("LAN") || name.localizedCaseInsensitiveContains("Ethernet") { return "Ethernet" }
        return name
    }

    /// "http://192.168.8.165:8787" -> "192.168.8.165:8787"
    nonisolated static func hostPart(_ url: String) -> String {
        url.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

// MARK: - Switch rows

/// A title, a status line under it, and a switch on the right, like the top of Tailscale's menu.
private struct MenuSwitchRow: View {
    let title: String
    let status: String
    var statusColor: Color = .secondary
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(width: 310, alignment: .leading)
    }
}

/// The viewer on or off, and how it's doing.
private struct ViewerSwitchRow: View {
    let engine: Engine

    var body: some View {
        MenuSwitchRow(title: "LfS Viewer", status: status, statusColor: color,
                      isOn: Binding { engine.isRunning } set: { $0 ? engine.start() : engine.stop() },
                      enabled: engine.phase != .stopping)
    }

    private var status: String {
        let phase = engine.phase
        guard phase == .live else {
            if case .failed = phase { return "Stopped unexpectedly. See the window." }
            return phase.title
        }
        // The count before the session name, so a long name is what gets cut short.
        var line = "Live"
        if engine.viewers.total > 0 { line += " · \(engine.viewers.total) watching" }
        if !engine.session.isEmpty { line += " · \(engine.session)" }
        return line
    }

    private var color: Color {
        switch engine.phase {
        case .captureOneLost, .failed: .red
        default: .secondary
        }
    }
}

/// Remote sharing on or off, and where it can be seen.
private struct SharingSwitchRow: View {
    let engine: Engine
    let tunnel: Tunnel
    @AppStorage(Prefs.remoteOn) private var remoteOn = false

    var body: some View {
        MenuSwitchRow(title: "Share Outside the Studio", status: status, statusColor: color,
                      isOn: Binding { remoteOn } set: { remoteOn = $0; tunnel.sync() },
                      enabled: remoteOn || tunnel.missing == nil)
    }

    private var status: String {
        switch tunnel.state {
        case .connected:
            let host = tunnel.publicURL.map(StatusMenu.hostPart) ?? "Connected"
            let remote = engine.viewers.remote
            return remote > 0 ? "\(host) · \(remote) remote" : host
        case .starting: return "Connecting to Cloudflare…"
        case .reconnecting: return "Reconnecting…"
        case .failed: return "Stopped. See the window."
        case .off: return remoteOn ? (tunnel.missing ?? "Starting…") : "Off"
        }
    }

    /// Coloured only when something's wrong, like the viewer's row.
    private var color: Color {
        switch tunnel.state {
        case .failed, .reconnecting: tunnel.state.color
        default: .secondary
        }
    }
}
