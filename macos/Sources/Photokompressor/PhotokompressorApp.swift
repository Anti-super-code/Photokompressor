import SwiftUI

@main
struct PhotokompressorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // The real windows (Options/Progress) are plain NSWindows created and
    // shown imperatively by AppCoordinator, mirroring App.xaml.cs's "one
    // borderless window, positioned at the cursor, shown programmatically"
    // model — that doesn't map onto SwiftUI's declarative WindowGroup, so
    // this Scene exists only to satisfy `App`'s requirement and stays empty.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
