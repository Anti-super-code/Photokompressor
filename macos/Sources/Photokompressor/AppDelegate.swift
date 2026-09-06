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
        // Must happen before anything touches libvips. VIPS_INIT does its
        // one-time GObject/operation-registry setup single-threaded, up
        // front; skipping it (as this did until now) means that setup
        // instead happens lazily, racily, on whichever background thread
        // first calls into libvips — which is exactly what
        // CompressionEngine's concurrent batch does. Confirmed by crash log:
        // a null-pointer deref inside vips_class_map_all, with multiple
        // compression threads simultaneously stuck in the same first-time
        // init path. The CLI target already did this; the app never did.
        VipsRuntime.ensureInitialized()
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
