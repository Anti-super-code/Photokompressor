import AppKit
import PhotokompressorCore

/// AppKit entry point — the Swift counterpart of App.xaml.cs's OnStartup.
/// `LSMultipleInstancesProhibited` (set in the Info.plist assembled at
/// packaging time) makes macOS route a second launch's files straight into
/// `application(_:open:)` on this instance instead of starting a new
/// process, which is what OnStartup's SingleInstance mutex/pipe existed to
/// approximate on Windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistration.ensureRegistered()
        NSApp.setActivationPolicy(.regular)
        coordinator.applicationDidFinishLaunching()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator.handleOpenFiles(urls.map { $0.path })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.focusOrShowEmpty()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
