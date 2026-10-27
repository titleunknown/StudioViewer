import AppKit
import SwiftUI

/// The app's windows (main, QR codes, Acknowledgments), made and shown from AppKit.
///
/// They used to be SwiftUI scenes opened with openWindow, but the menu bar menu is an AppKit NSMenu
/// (see StatusMenu: SwiftUI's menu bar menus can't show switch rows), and AppKit code can't call
/// openWindow. Each window hosts the same SwiftUI views as before, is kept when closed and reused
/// when shown again (QR code windows only until another is shown).
@MainActor
final class Windows {
    static let shared = Windows()

    /// Set by AppDelegate at launch: what the main window's views read.
    var engine: Engine!
    var tunnel: Tunnel!
    var navigation: Navigation!

    private var main: NSWindow?
    private var acknowledgments: NSWindow?
    private var qr: [String: NSWindow] = [:]

    /// Shows the main window, optionally on one of its panels.
    func showMain(panel: Panel? = nil) {
        if let panel { navigation.panel = panel }
        if main == nil {
            let view = MainWindow()
                .environment(engine)
                .environment(tunnel)
                .environment(navigation)
            let window = make(view, title: "LfS Viewer", size: NSSize(width: 820, height: 680), resizable: true)
            window.setFrameAutosaveName("LfS Viewer main window")  // remembers size and place between launches
            main = window
        }
        present(main!)
    }

    func showAcknowledgments() {
        if acknowledgments == nil {
            acknowledgments = make(AcknowledgmentsView(), title: "Acknowledgments",
                                   size: NSSize(width: 640, height: 620), resizable: true)
        }
        present(acknowledgments!)
    }

    /// A large QR code for one address; one window per address.
    func showQR(_ url: String) {
        // Closed ones go: a temporary link's address is new each time sharing starts.
        qr = qr.filter { $0.value.isVisible || $0.value.isMiniaturized }
        if qr[url] == nil {
            qr[url] = make(QRWindow(url: url), title: "QR Code", size: nil, resizable: false)
        }
        present(qr[url]!)
    }

    private func make(_ view: some View, title: String, size: NSSize?, resizable: Bool) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        // Resizable windows take their minimum size from the view; fixed ones its exact size.
        hosting.sizingOptions = resizable ? [.minSize] : [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        if let size { window.setContentSize(size) }
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        DockIcon.bringForward()
        window.makeKeyAndOrderFront(nil)
    }
}
