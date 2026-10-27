import SwiftUI

/// The Viewers panel: every browser watching right now (what it is, where it's from, who and
/// roughly where for remote visitors, the folder and photo it's on, how long it has been
/// connected, what it has rated and how much the viewer has sent it), with Remove and Stop
/// Rating; then the devices that left in the last hour; then the removed ones, with Unblock.
struct ViewersSection: View {
    @Environment(Engine.self) private var engine
    @State private var message: String?

    private var connected: [Device] { engine.devices.filter { !$0.blocked && $0.left != true } }
    private var recentlyLeft: [Device] { engine.devices.filter { !$0.blocked && $0.left == true } }
    private var removed: [Device] { engine.devices.filter(\.blocked) }

    var body: some View {
        Section {
            if !engine.isRunning {
                Text("Start the viewer to see who's watching.").foregroundStyle(.secondary)
            } else if connected.isEmpty {
                Text("No one is watching right now.").foregroundStyle(.secondary)
            } else {
                ForEach(connected) { device in
                    DeviceRow(device: device, remove: { remove(device) }, setRating: { setRating(device, $0) })
                }
            }
            if let message {
                Text(message).foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Connected now")
                Spacer()
                if !connected.isEmpty {
                    let total = connected.reduce(0) { $0 + ($1.bytes ?? 0) }
                    Text("\(connected.count) \(connected.count == 1 ? "device" : "devices") · \(Self.size(total)) sent")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } footer: {
            Text(footer).sectionFooter()
        }

        if !recentlyLeft.isEmpty {
            Section {
                ForEach(recentlyLeft) { device in
                    DeviceRow(device: device, remove: { remove(device) }, setRating: { setRating(device, $0) })
                }
            } header: {
                Text("Recently left")
            } footer: {
                Text("Browsers that closed the viewer, or went to sleep, in the last hour. They move back up if they return.")
                    .sectionFooter()
            }
        }

        if !removed.isEmpty {
            Section {
                ForEach(removed) { device in
                    HStack {
                        DeviceLabel(device: device)
                        Spacer()
                        Button("Unblock") { perform(into: $message) { await engine.unblockDevice(device.id) } }
                    }
                }
            } header: {
                Text("Removed")
            } footer: {
                Text("""
                    A removed device sees "This device was removed" until you unblock it. Someone could still \
                    get back in by clearing their browser's data or using another browser: to keep a person \
                    out for good, take them off your Cloudflare Access policy (remote), or change the PIN or \
                    viewing code.
                    """)
                    .sectionFooter()
            }
        }
    }

    private var footer: String {
        var text = "Data sent since each browser connected. For remote visitors, click the address to look it up, or the place to see it on a map."
        // Cloudflare only sends the city when the zone adds visitor location headers.
        if engine.devices.contains(where: { $0.place == .remote && !$0.blocked && ($0.city ?? "").isEmpty }) {
            text += " To see their city as well as their country, turn on \"Add visitor location headers\" in the Cloudflare dashboard (your domain › Rules › Settings › Managed Transforms)."
        }
        return text
    }

    private func remove(_ device: Device) {
        perform(into: $message) { await engine.removeDevice(device.id) }
    }

    private func setRating(_ device: Device, _ allow: Bool) {
        perform(into: $message) { await engine.setDeviceRating(device.id, allow: allow) }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// "4 min", "1 hr, 5 min"; under a minute, "under a minute".
    static func duration(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "under a minute" }
        return Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Icon, name and where-from for a device, shared by every list.
private struct DeviceLabel: View {
    let device: Device

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 30)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.place == .thisMac ? "\(device.name) · This Mac" : device.name)
                whereFrom.font(.caption).foregroundStyle(.secondary)
                if device.blocked, let at = device.blockedAt {
                    Text("Removed \(Date(timeIntervalSince1970: at).formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Remote · client@example.com · 203.0.113.7 · Austin, Texas, United States": the address opens
    /// ipinfo.io, the place opens Apple Maps.
    @ViewBuilder private var whereFrom: some View {
        switch device.place {
        case .thisMac:
            Text("This Mac")
        case .network:
            Text("Your network · \(device.ip)").textSelection(.enabled)
        case .remote:
            HStack(spacing: 4) {
                Text("Remote ·")
                if !device.email.isEmpty {
                    Text("\(device.email) ·").textSelection(.enabled)
                }
                if let url = device.ipInfoURL {
                    Link(device.ip, destination: url)
                        .foregroundStyle(.link)
                        .help("Look up \(device.ip) on ipinfo.io")
                } else {
                    Text(device.ip)
                }
                if let location = device.location {
                    Text("·")
                    if let map = device.mapURL {
                        Link(location, destination: map)
                            .foregroundStyle(.link)
                            .help("Show on a map (roughly: from the visitor's IP address)")
                    } else {
                        Text(location)
                    }
                }
            }
            .lineLimit(1)
        }
    }

    private var symbol: String {
        let n = device.name
        if n.hasPrefix("iPhone") || n.hasPrefix("Android") { return "iphone" }
        if n.hasPrefix("iPad") { return "ipad" }
        if n.hasPrefix("Mac") { return device.place == .thisMac ? "desktopcomputer" : "laptopcomputer" }
        if n.hasPrefix("Windows") || n.hasPrefix("Linux") || n.hasPrefix("Chromebook") { return "pc" }
        return "display"
    }
}

private struct DeviceRow: View {
    let device: Device
    let remove: () -> Void
    let setRating: (Bool) -> Void
    /// The confirmation lives on the row itself: SwiftUI never shows one attached to an EmptyView.
    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                DeviceLabel(device: device)
                // Redrawn each minute, so "connected 25 min" and "left 4 min ago" keep up.
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(watching).textSelection(.enabled)
                        Text(details(now: context.date))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, 42)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ViewersSection.size(device.bytes ?? 0)).monospacedDigit()
                Text("sent").font(.caption).foregroundStyle(.secondary)
            }
            if device.place != .thisMac {
                Menu {
                    if device.left != true {
                        if device.ratingBlocked == true {
                            Button("Allow Rating on This Device") { setRating(true) }
                        } else {
                            Button("Stop Rating on This Device") { setRating(false) }
                        }
                    }
                    if device.place == .remote {
                        Divider()
                        if let url = device.ipInfoURL {
                            Button("Look Up \(device.ip)") { NSWorkspace.shared.open(url) }
                        }
                        if let map = device.mapURL {
                            Button("Show on Map") { NSWorkspace.shared.open(map) }
                        }
                        Button("Copy IP Address") { Address.copy(device.ip) }
                    }
                    Divider()
                    Button("Remove…", role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(device.left == true ? "Remove this device so it can't come back" : "Remove this device, or stop its rating")
                .accessibilityLabel("Actions for \(device.name)")
            }
        }
        .confirmationDialog("Remove \(device.name)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text(device.left == true
                 ? "It can't watch again until you unblock it."
                 : "It stops showing the shoot right away and can't watch again until you unblock it.")
        }
    }

    /// "Capture/NEO · NEO_0398.jpg" (the folder, then the photo on its screen)
    private var watching: String {
        let folder = device.folder ?? "", photo = device.photo ?? ""
        let place = [folder, photo].filter { !$0.isEmpty }.joined(separator: " · ")
        if place.isEmpty { return device.left == true ? "Left" : "Choosing a folder" }
        return device.left == true ? "Was on \(place)" : "On \(place)"
    }

    /// "Connected 25 min · rated 12, tagged 3 · can rate", or for one that left,
    /// "Left 4 min ago, after 25 min · rated 12"
    private func details(now: Date) -> String {
        var parts: [String] = []
        if device.left == true, let last = device.lastSeen {
            var line = "Left \(ViewersSection.duration(now.timeIntervalSince1970 - last)) ago"
            if let since = device.since, last - since >= 60 { line += ", after \(ViewersSection.duration(last - since))" }
            parts.append(line.replacingOccurrences(of: "under a minute ago", with: "just now"))
        } else if let since = device.since {
            parts.append("Connected \(ViewersSection.duration(now.timeIntervalSince1970 - since))")
        }
        let ratings = device.ratings ?? 0, tags = device.tags ?? 0
        let changes = [ratings > 0 ? "rated \(ratings)" : nil, tags > 0 ? "tagged \(tags)" : nil].compactMap { $0 }
        if !changes.isEmpty { parts.append(changes.joined(separator: ", ")) }
        if device.left != true {
            if device.ratingBlocked == true {
                parts.append("rating stopped")
            } else if device.canRate == true {
                parts.append(device.unlocked == true ? "can rate (PIN)" : "can rate")
            } else {
                parts.append("view only")
            }
        }
        return parts.joined(separator: " · ")
    }
}
