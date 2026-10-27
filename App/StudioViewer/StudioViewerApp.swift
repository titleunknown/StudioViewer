import SwiftUI

/// StudioViewer: a menu bar app that runs the StudioViewer (studio_viewer.py) for you.
/// Starting, stopping, the addresses to share (with QR codes), who may rate, and notifications
/// when something goes wrong. It lives in the menu bar; the window is optional.
@main
struct StudioViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The windows and the menu bar menu are AppKit (see Windows and StatusMenu). This scene
        // never shows: it's here because an App needs one, and it carries the app menu's
        // About and Settings… commands, which open the main window on those panels.
        Settings { EmptyView() }
            .commands { AppMenuCommands() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine: Engine
    let tunnel: Tunnel
    let navigation: Navigation
    private let notifier = Notifier()
    private var statusMenu: StatusMenu?

    override init() {
        // Before anything reads preferences: Tunnel and Navigation do as they're made.
        Migration.run()
        UserDefaults.standard.register(defaults: Prefs.defaults)
        engine = Engine()
        tunnel = Tunnel()
        navigation = Navigation()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing a command to a viewer that has just died must fail, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        notifier.engine = engine
        engine.onAlert = { [notifier] in notifier.handle($0) }
        notifier.setUp()
        // Remote sharing follows the viewer: on while it runs (if switched on), off when it stops.
        Tunnel.stopLeftover()
        tunnel.engine = engine
        tunnel.onAlert = { [notifier] in notifier.handle($0) }
        engine.onRunningChange = { [tunnel] in tunnel.sync() }
        DockIcon.watchWindows()
        Windows.shared.engine = engine
        Windows.shared.tunnel = tunnel
        Windows.shared.navigation = navigation
        statusMenu = StatusMenu(engine: engine, tunnel: tunnel)
        if UserDefaults.standard.bool(forKey: Prefs.showWindowAtLaunch) {
            Windows.shared.showMain()
        }
        if UserDefaults.standard.bool(forKey: Prefs.startOnLaunch) {
            engine.start()
        }
        UpdateChecker.shared.startAutoChecks()  // does nothing unless switched on in About
    }

    /// Clicking the Dock icon with no window open shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Windows.shared.showMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keep running in the menu bar
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The viewer also stops by itself when its stdin closes as the app exits; cloudflared doesn't.
        tunnel.stopNow()
        engine.stop()
    }
}

/// The Dock icon (and the app menu) appear while a window is open, or always if the user asks.
/// Otherwise StudioViewer is only in the menu bar.
enum DockIcon {
    static func watchWindows() {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After willClose the window is still visible; look once it has gone.
                DispatchQueue.main.async { MainActor.assumeIsolated { update() } }
            }
        }
        update()
    }

    static func update() {
        let always = UserDefaults.standard.bool(forKey: Prefs.alwaysShowInDock)
        let windowOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        let policy: NSApplication.ActivationPolicy = always || windowOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    /// Before opening a window from the menu bar: become a regular app so it comes to the front.
    static func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
