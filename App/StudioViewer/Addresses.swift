import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import SystemConfiguration

/// One address people can open the viewer at, labelled for humans ("Wi-Fi", "Apple devices").
struct Address: Identifiable, Hashable {
    var label: String
    var url: String
    var id: String { url }

    /// This Mac first, then one per network connection, then the Bonjour name.
    static func list(_ urls: ViewerURLs?) -> [Address] {
        guard let urls else { return [] }
        var list = [Address(label: "This Mac", url: urls.local)]
        list += urls.network.map { Address(label: interfaceName($0.interface), url: $0.url) }
        if let bonjour = urls.bonjour {
            list.append(Address(label: "Apple devices", url: bonjour))
        }
        return list
    }

    /// The addresses worth sharing with other devices (not localhost).
    static func shareable(_ urls: ViewerURLs?) -> [Address] {
        list(urls).filter { $0.url != urls?.local }
    }

    /// "en0" -> "Wi-Fi", as System Settings names it.
    private static func interfaceName(_ bsd: String) -> String {
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let match = all.first { SCNetworkInterfaceGetBSDName($0) as String? == bsd }
        let name = match.flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? }
        return name.map { "\($0) (\(bsd))" } ?? bsd
    }

    static func copy(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

enum QRCode {
    /// A crisp QR code: one pixel per module, so draw it with `.interpolation(.none)`.
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}

/// A window with a large QR code for one address, to scan from a phone or tablet.
struct QRWindow: View {
    let url: String
    @State private var fullscreen = false
    @State private var copied = false

    /// Fullscreen mode is the clean client view (see the README); ?fullscreen opens straight into it.
    private var shown: String { fullscreen ? url + "/?fullscreen" : url }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image = QRCode.image(for: shown) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .accessibilityLabel("QR code for \(shown)")
                } else {
                    Text("Couldn't make a QR code.")
                }
            }
            .frame(width: 300, height: 300)
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))

            Text(shown)
                .font(.title3.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.center)

            Text(url.hasPrefix("https://")
                 ? "Scan with a phone or tablet camera, from anywhere. They'll need the viewing code too."
                 : "Scan with the camera on a phone or tablet on the same network.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Open in fullscreen mode (for a client screen)", isOn: $fullscreen)

            HStack {
                Button(copied ? "Copied" : "Copy Address") {
                    Address.copy(shown)
                    copied = true
                }
                Button("Open in Browser") { Address.open(shown) }
            }
        }
        .padding(28)
        .onChange(of: fullscreen) { copied = false }
        .navigationTitle("QR Code")
    }
}
