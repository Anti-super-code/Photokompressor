import AppKit
import SwiftUI
import Combine

/// Row/header measurements shared between here and GalleryTrayView.swift's
/// actual layout, so the window can be sized to fit its SwiftUI content
/// analytically instead of round-tripping through a live measurement pass.
/// Keep these in sync with GalleryTrayView's header/row paddings if either
/// changes.
enum GalleryTrayLayout {
    static let width: CGFloat = 260
    /// header's .padding(top: 20) + RoundGlyphButton's 46pt height + .padding(bottom: 10)
    static let headerHeight: CGFloat = 76
    /// GalleryRow's 52x52 thumbnail is its tallest element.
    static let rowHeight: CGFloat = 52
    static let rowSpacing: CGFloat = 10
    static let listBottomPadding: CGFloat = 16
    static let minHeight: CGFloat = headerHeight + listBottomPadding

    static func contentHeight(forFileCount count: Int) -> CGFloat {
        guard count > 0 else { return minHeight }
        let rowsHeight = CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
        return headerHeight + rowsHeight + listBottomPadding
    }
}

/// The borderless panel that slides out to the left of the main Options
/// window when the gallery icon is tapped. Sized to fit its rows exactly,
/// capped at the parent's height (past that, GalleryTrayView's ScrollView
/// takes over). Attached as an AppKit child window of the parent (so it
/// tracks the parent when dragged, and disappears automatically if the
/// parent closes).
final class GalleryTrayWindow: NSWindow {
    private static let gapFromParent: CGFloat = 10

    private var filesCancellable: AnyCancellable?

    init(attachedTo parent: NSWindow, viewModel: OptionsViewModel, onClose: @escaping () -> Void) {
        let height = min(GalleryTrayLayout.contentHeight(forFileCount: viewModel.files.count), parent.frame.height)
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

        let hosting = NSHostingView(rootView: GalleryTrayView(viewModel: viewModel, onClose: onClose))
        hosting.frame = NSRect(x: 0, y: 0, width: GalleryTrayLayout.width, height: height)
        contentView = hosting

        reposition(relativeTo: parent.frame)
        parent.addChildWindow(self, ordered: .above)

        filesCancellable = viewModel.$files.sink { [weak self] files in
            self?.updateHeight(forFileCount: files.count)
        }
    }

    /// Left of the parent, top edges aligned (so both windows' headers
    /// stay level regardless of the tray's own height).
    func reposition(relativeTo parentFrame: NSRect) {
        let x = parentFrame.minX - GalleryTrayLayout.width - Self.gapFromParent
        let y = parentFrame.maxY - frame.height
        setFrame(NSRect(x: x, y: y, width: GalleryTrayLayout.width, height: frame.height), display: true)
    }

    private func updateHeight(forFileCount count: Int) {
        // `parent` here is AppKit's own NSWindow property (set by
        // addChildWindow), not one of ours.
        guard let parent else { return }
        let newHeight = min(GalleryTrayLayout.contentHeight(forFileCount: count), parent.frame.height)
        guard abs(newHeight - frame.height) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y = parent.frame.maxY - newHeight
        newFrame.size.height = newHeight
        setFrame(newFrame, display: true, animate: true)
    }

    override var canBecomeKey: Bool { true }
}
