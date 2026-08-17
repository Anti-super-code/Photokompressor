import SwiftUI
import ImageIO
import AppKit

/// The tray's content: a vertical list of the selected photos (real decoded
/// thumbnails, not generic file icons — this app is about photos, so it
/// should look like one), each with its filename, size, and a remove
/// button, plus a trailing row to add more. Vertical because the tray sits
/// beside the main window at the same height, not a short horizontal strip.
struct GalleryTrayView: View {
    @ObservedObject var viewModel: OptionsViewModel
    var onClose: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Theme.trayBg)
            .shadow(color: Color(hex: 0x243044, opacity: 0.22), radius: 20, x: 0, y: 6)
            .overlay(
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(viewModel.files, id: \.self) { path in
                                GalleryRow(path: path) {
                                    viewModel.removeFile(path)
                                }
                            }
                        }
                        // Extra top clearance so the top-trailing close
                        // button (overlaid separately, not part of this
                        // flow) has room above the first row instead of
                        // crowding its remove button.
                        .padding(.top, 56)
                        .padding([.horizontal, .bottom], 16)
                    }
                    AddMoreRow {
                        viewModel.addFilesViaPicker()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            )
            .overlay(alignment: .topTrailing) {
                RoundGlyphButton(kind: .close, action: onClose)
                    .padding(2)
            }
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
                    Circle().fill(Theme.danger)
                    Path { p in
                        p.move(to: CGPoint(x: 5, y: 5)); p.addLine(to: CGPoint(x: 11, y: 11))
                        p.move(to: CGPoint(x: 11, y: 5)); p.addLine(to: CGPoint(x: 5, y: 11))
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

private struct AddMoreRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.textLo, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: 13, y: 5)); p.addLine(to: CGPoint(x: 13, y: 21))
                            p.move(to: CGPoint(x: 5, y: 13)); p.addLine(to: CGPoint(x: 21, y: 13))
                        }
                        .stroke(Theme.textMid, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 26, height: 26)
                    )
                Text("Add photos")
                    .font(Theme.font(size: 12, .regular))
                    .foregroundColor(Theme.textMid)
                Spacer()
            }
            // A stroke-only (unfilled) shape like the dashed square above
            // has no rendered interior, so without this its "hollow" middle
            // doesn't reliably count as part of the button's hit-testable
            // area — the row clicked everywhere except the square itself.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
