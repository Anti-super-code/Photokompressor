import AppKit
import SwiftUI

/// A borderless, transparent, cursor-positioned window hosting SwiftUI
/// content — the AppKit equivalent of OptionsWindow.xaml/ProgressWindow.xaml's
/// `WindowStyle="None" AllowsTransparency="True" Topmost="True"` plus
/// CursorPositioner. `isMovableByWindowBackground` replaces WPF's manual
/// `OnChromeDrag` handler: AppKit already only drags from areas no control
/// claimed the click first, which is exactly the behavior that handler
/// hand-rolled.
final class ChromelessWindow: NSWindow {
    init<Content: View>(width: CGFloat, height: CGFloat, shadowMargin: CGFloat, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the card itself draws a drop shadow in SwiftUI
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        contentView = hosting

        let frame = WindowPositioning.frameNearCursor(width: width, height: height, shadowMargin: shadowMargin)
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
