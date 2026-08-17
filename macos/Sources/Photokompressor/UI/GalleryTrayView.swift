import SwiftUI
import ImageIO
import AppKit

/// Reports the *actual* rendered height of the header and the row list (each
/// added, via .reduce below) up to GalleryTrayWindow, which resizes itself
/// to match — real measurement rather than a hand-computed estimate from
/// row/spacing constants, which drifted from the real layout in practice
/// (off by enough to make a 2-3 row list scroll when it should have fit).
private struct GalleryContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    func measuringHeight<Key: PreferenceKey>(into key: Key.Type) -> some View where Key.Value == CGFloat {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: Key.self, value: geo.size.height)
            }
        )
    }
}

/// The tray's content: a vertical list of the selected photos (real decoded
/// thumbnails, not generic file icons — this app is about photos, so it
/// should look like one), each with its filename, size, and a remove
/// button. Vertical because the tray sits beside the main window, sized to
/// its contents up to the main window's height (see GalleryTrayWindow).
struct GalleryTrayView: View {
    @ObservedObject var viewModel: OptionsViewModel
    var onClose: () -> Void
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Theme.trayBg)
            .shadow(color: Color(hex: 0x243044, opacity: 0.22), radius: 20, x: 0, y: 6)
            .overlay(
                VStack(spacing: 0) {
                    header
                        .measuringHeight(into: GalleryContentHeightKey.self)
                    // Window height is sized to fit these rows exactly
                    // (measured below), clamped to the main window's height
                    // — so this ScrollView only ever actually scrolls once
                    // that clamp kicks in.
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: GalleryTrayLayout.rowSpacing) {
                            ForEach(viewModel.files, id: \.self) { path in
                                GalleryRow(path: path) {
                                    viewModel.removeFile(path)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, GalleryTrayLayout.listBottomPadding)
                        .measuringHeight(into: GalleryContentHeightKey.self)
                    }
                }
            )
            .onPreferenceChange(GalleryContentHeightKey.self, perform: onContentHeightChange)
    }

    /// Same top/leading/trailing insets as the main window's own header
    /// (OptionsView's outer EdgeInsets(top: 20, leading: 26, trailing: 26))
    /// and the same WindowDragBackground-behind-the-row trick, so the tray
    /// reads as the same chrome as the main window — including being
    /// draggable from here, not just tracking the main window's drags.
    private var header: some View {
        HStack(alignment: .center) {
            SectionLabel(text: "SELECTIONS")
                .allowsHitTesting(false)
            Spacer()
            RoundGlyphButton(kind: .close, hoverStyle: .neutral, action: onClose)
        }
        .padding(.top, 20)
        .padding(.leading, 26)
        .padding(.trailing, 26)
        .padding(.bottom, 10)
        .background(WindowDragBackground())
    }
}

private struct GalleryRow: View {
    let path: String
    let onRemove: () -> Void

    @State private var image: NSImage?

    private var fileName: String { (path as NSString).lastPathComponent }
    private var sizeText: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs?[.size] as? Int).map(Int64.init) ?? 0
        return FileSizeFormatting.string(bytes)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.sunken)
                .frame(width: 52, height: 52)
                .overlay(
                    Group {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: fileName)
                    .font(Theme.font(size: 11.5, .regular))
                    .foregroundColor(Theme.textMid)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: sizeText)
                    .font(Theme.font(size: 10.5, .light))
                    .foregroundColor(Theme.textLo)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                ZStack {
                    Circle().fill(Theme.dangerDeep)
                    // Centered on the 18x18 frame's midpoint (9,9): the
                    // previous 5..11 span was centered on 8,8, visibly off
                    // by a pixel once this button got looked at up close.
                    Path { p in
                        p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 12, y: 12))
                        p.move(to: CGPoint(x: 12, y: 6)); p.addLine(to: CGPoint(x: 6, y: 12))
                    }
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let path = self.path
        // CGImage (unlike NSImage on macOS < 14) is Sendable, so the
        // decode happens off-main and only the final wrap-into-NSImage
        // happens back here.
        let cgThumb = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceShouldCache: false,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let cgThumb {
            image = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        }
    }
}
