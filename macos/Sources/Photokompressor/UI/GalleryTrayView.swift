import SwiftUI
import ImageIO
import AppKit

/// The tray's content: a horizontal gallery of the selected photos (real
/// decoded thumbnails, not generic file icons — this app is about photos,
/// so it should look like one), each with its filename, size, and a remove
/// button, plus a trailing tile to add more.
struct GalleryTrayView: View {
    @ObservedObject var viewModel: OptionsViewModel

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Theme.trayBg)
            .shadow(color: Color(hex: 0x243044, opacity: 0.22), radius: 20, x: 0, y: 6)
            .overlay(
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.files, id: \.self) { path in
                            GalleryThumbnail(path: path) {
                                viewModel.removeFile(path)
                            }
                        }
                        AddMoreTile {
                            viewModel.addFilesViaPicker()
                        }
                    }
                    .padding(18)
                }
            )
    }
}

private struct GalleryThumbnail: View {
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
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.sunken)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Group {
                            if let image {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: onRemove) {
                    ZStack {
                        Circle().fill(Theme.danger)
                        Path { p in
                            p.move(to: CGPoint(x: 5, y: 5)); p.addLine(to: CGPoint(x: 11, y: 11))
                            p.move(to: CGPoint(x: 11, y: 5)); p.addLine(to: CGPoint(x: 5, y: 11))
                        }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
            .frame(width: 96, height: 96)

            Text(verbatim: fileName)
                .font(Theme.font(size: 10.5, .regular))
                .foregroundColor(Theme.textMid)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 96)
            Text(verbatim: sizeText)
                .font(Theme.font(size: 10, .light))
                .foregroundColor(Theme.textLo)
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
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceShouldCache: false,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let cgThumb {
            image = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
        }
    }
}

private struct AddMoreTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.textLo, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: 24, y: 12)); p.addLine(to: CGPoint(x: 24, y: 36))
                            p.move(to: CGPoint(x: 12, y: 24)); p.addLine(to: CGPoint(x: 36, y: 24))
                        }
                        .stroke(Theme.textMid, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 48, height: 48)
                    )
                Text("Add photos")
                    .font(Theme.font(size: 10.5, .regular))
                    .foregroundColor(Theme.textMid)
                Text(verbatim: " ")
                    .font(Theme.font(size: 10, .light))
            }
        }
        .buttonStyle(.plain)
    }
}
