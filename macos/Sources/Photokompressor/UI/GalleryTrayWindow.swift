import AppKit
import SwiftUI

enum GalleryTrayLayout {
    static let width: CGFloat = 260
    static let rowSpacing: CGFloat = 10
    static let listBottomPadding: CGFloat = 16
    /// Only used for the very first frame, before GalleryTrayView's real
    /// measured height (see GalleryContentHeightKey) arrives — a rough
    /// guess close enough to avoid a visible pop on first appearance. Actual
    /// sizing after that is measured, not computed from row/header
    /// constants: an earlier version tried to keep those in sync by hand
    /// and drifted from the real SwiftUI layout enough that a 2-3 row list
    /// would scroll when it should have fit.
    static let initialHeightEstimate: CGFloat = 220
}

/// The borderless panel that slides out to the left of the main Options
/// window when the gallery icon is tapped. Sized to fit its rows exactly
/// (GalleryTrayView measures and reports its own content height), capped at
/// the parent's height — past that, GalleryTrayView's ScrollView takes
/// over. Attached as an AppKit child window of the parent (so it tracks the
/// parent when dragged, and disappears automatically if the parent closes).
final class GalleryTrayWindow: NSWindow {
    private static let gapFromParent: CGFloat = 10

    init(attachedTo parent: NSWindow, viewModel: OptionsViewModel, onClose: @escaping () -> Void) {
        let height = min(GalleryTrayLayout.initialHeightEstimate, parent.frame.height)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: GalleryTrayLayout.width, height: height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        // Not AppKit's native window shadow — matches ChromelessWindow's
        // own reasoning: the card draws its own drop shadow in SwiftUI
        // (GalleryTrayView's .shadow(...) on the RoundedRectangle). AppKit's
        // shadow, computed from the content's rendered alpha mask, doesn't
        // recompute cleanly around that rounded shape on every resize —
        // it left a stale, jagged shadow notch at the corners after the
        // tray started resizing itself to fit its content.
        hasShadow = false
        isMovableByWindowBackground = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let hosting = NSHostingView(rootView: GalleryTrayView(viewModel: viewModel, onClose: onClose, onContentHeightChange: { [weak self] measured in
            self?.applyMeasuredHeight(measured)
        }))
        hosting.frame = NSRect(x: 0, y: 0, width: GalleryTrayLayout.width, height: height)
        contentView = hosting

        reposition(relativeTo: parent.frame)
        parent.addChildWindow(self, ordered: .above)
    }

    /// Left of the parent, top edges aligned (so both windows' headers
    /// stay level regardless of the tray's own height).
    func reposition(relativeTo parentFrame: NSRect) {
        let x = parentFrame.minX - GalleryTrayLayout.width - Self.gapFromParent
        let y = parentFrame.maxY - frame.height
        setFrame(NSRect(x: x, y: y, width: GalleryTrayLayout.width, height: frame.height), display: true)
    }

    private func applyMeasuredHeight(_ measuredContentHeight: CGFloat) {
        // `parent` here is AppKit's own NSWindow property (set by
        // addChildWindow), not one of ours.
        guard let parent, measuredContentHeight > 0 else { return }
        let newHeight = min(measuredContentHeight, parent.frame.height)
        guard abs(newHeight - frame.height) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y = parent.frame.maxY - newHeight
        newFrame.size.height = newHeight
        // Not animated: an animated resize while the user is mid-click on a
        // row's remove button shifts that row under the cursor between
        // mouseDown and mouseUp, which can land the click on a neighboring
        // row's button instead — an immediate resize can't race a click
        // like that.
        setFrame(newFrame, display: true)
    }

    override var canBecomeKey: Bool { true }
}
