import AppKit
import SwiftUI

/// The borderless panel that slides out to the left of the main Options
/// window when the gallery icon is tapped, matching the parent's height.
/// Attached as an AppKit child window of the parent (so it tracks the
/// parent when dragged, and disappears automatically if the parent closes).
final class GalleryTrayWindow: NSWindow {
    static let width: CGFloat = 260
    private static let gapFromParent: CGFloat = 10

    init<Content: View>(attachedTo parent: NSWindow, @ViewBuilder content: () -> Content) {
        let height = parent.frame.height
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        contentView = hosting

        reposition(relativeTo: parent.frame)
        parent.addChildWindow(self, ordered: .above)
    }

    /// Left of the parent, same height, bottom edges aligned.
    func reposition(relativeTo parentFrame: NSRect) {
        let x = parentFrame.minX - Self.width - Self.gapFromParent
        let y = parentFrame.minY
        setFrame(NSRect(x: x, y: y, width: Self.width, height: parentFrame.height), display: true)
    }

    override var canBecomeKey: Bool { true }
}
