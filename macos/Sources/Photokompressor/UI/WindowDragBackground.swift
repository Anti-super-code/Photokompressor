import SwiftUI
import AppKit

/// A view modifier that makes the whole tagged view draggable as if it were
/// window chrome — the SwiftUI-native replacement for both
/// `NSWindow.isMovableByWindowBackground` (which didn't defer to SwiftUI
/// gesture recognizers layered on top, so the size slider dragged the whole
/// window) and an `NSViewRepresentable`-based background view (which, as an
/// intrinsic-size-less NSView, either got shut out entirely by a ScrollView
/// claiming every click in its bounds, or — placed as a `ZStack` sibling
/// instead of a `.background()` — expanded to swallow far more layout space
/// than intended). Both were real bugs hit during hands-on testing.
///
/// This works entirely inside SwiftUI's own gesture system instead: attach
/// directly to the exact area that should be draggable via
/// `.contentShape(Rectangle())` (so empty-looking space between/around text
/// counts too, not just where something is actually painted) plus a plain
/// `DragGesture`, manually repositioning the window by the drag's
/// translation. A small non-zero minimum distance means a plain click
/// (no movement) doesn't fire `onChanged` at all, so a `Button` nested
/// inside the same view still gets first refusal on an ordinary click —
/// only an actual drag motion is intercepted here.
struct WindowDraggable: ViewModifier {
    @State private var startOrigin: CGPoint?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard let window = NSApp.keyWindow else { return }
                        if startOrigin == nil {
                            startOrigin = window.frame.origin
                        }
                        guard let start = startOrigin else { return }
                        // SwiftUI's drag translation is in a top-left-down
                        // coordinate space; AppKit's window origin is
                        // bottom-left-up, so Y moves opposite to X.
                        window.setFrameOrigin(CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y - value.translation.height
                        ))
                    }
                    .onEnded { _ in
                        startOrigin = nil
                    }
            )
    }
}

extension View {
    func windowDraggable() -> some View {
        modifier(WindowDraggable())
    }
}
