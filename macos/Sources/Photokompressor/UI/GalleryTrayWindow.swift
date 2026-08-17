import AppKit
import SwiftUI

/// The borderless panel that drops down below the main Options window when
/// the gallery icon is tapped. Attached as an AppKit child window of the
/// parent (so it tracks the parent when dragged, and disappears
/// automatically if the parent closes), positioned directly below it and
/// extending further left than the parent's own left edge — "stretches to
/// the left" — with its right edge aligned to the parent's right edge.
final class GalleryTrayWindow: NSWindow {
    private static let width: CGFloat = 680
    private static let height: CGFloat = 168
    private static let gapBelowParent: CGFloat = 10

    init<Content: View>(attachedTo parent: NSWindow, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
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
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        contentView = hosting

        reposition(relativeTo: parent.frame)
        parent.addChildWindow(self, ordered: .above)
    }

    func reposition(relativeTo parentFrame: NSRect) {
        let x = parentFrame.maxX - Self.width
        let y = parentFrame.minY - Self.height - Self.gapBelowParent
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
}
