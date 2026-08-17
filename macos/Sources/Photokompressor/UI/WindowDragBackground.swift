import SwiftUI
import AppKit

/// Place at the very bottom of the card's ZStack, behind every real control.
///
/// `NSWindow.isMovableByWindowBackground` doesn't reliably defer to SwiftUI's
/// own gesture recognizers hosted inside the same NSHostingView — dragging a
/// custom control like the size slider ended up moving the whole window
/// instead of the thumb, because AppKit's window-drag hit-testing doesn't
/// know a SwiftUI DragGesture farther up the z-order already claimed that
/// mouseDown. This replaces the blanket window-level flag with an explicit
/// lowest-z-order view, so real controls (drawn on top, each owning its own
/// gesture/contentShape) get first claim, and only genuinely empty card
/// space falls through to start a window drag — the direct equivalent of
/// OnChromeDrag's DragMove() call in the original WPF windows.
struct WindowDragBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
