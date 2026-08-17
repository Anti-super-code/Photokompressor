import SwiftUI
import UniformTypeIdentifiers
import PhotokompressorCore

/// Direct port of OptionsWindow.xaml — same layout, same copy, same
/// behavior. `NeuToggle`/`SegmentedPicker`/etc. are the SwiftUI ports of
/// Theme.xaml's styles (see Controls.swift).
struct OptionsView: View {
    @ObservedObject var viewModel: OptionsViewModel
    @State private var dropTargeted = false

    private let sizeRange: ClosedRange<Double> = 50...3000

    var body: some View {
        ZStack {
            WindowDragBackground()

            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.bg)
                .shadow(color: Color(hex: 0x243044, opacity: 0.3), radius: 34, x: 0, y: 7)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                if viewModel.infoShowing {
                    InfoView(viewModel: viewModel)
                } else {
                    body_
                    footer
                }
            }
            .padding(EdgeInsets(top: 20, leading: 26, bottom: 24, trailing: 26))

            if dropTargeted {
                dropOverlay
            }
        }
        .frame(width: 500, height: 824)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PHOTOKOMPRESSOR")
                    .font(Theme.font(size: 27, .extraLight))
                    .foregroundColor(Theme.textHi)
                if !viewModel.infoShowing {
                    HStack(spacing: 6) {
                        Text(viewModel.subtitleText)
                            .font(Theme.font(size: 13, .light))
                            .foregroundColor(Theme.textLo)
                        if !viewModel.files.isEmpty {
                            Button("Deselect all") { viewModel.deselectAll() }
                                .buttonStyle(LinkButtonStyle())
                        }
                    }
                }
            }
            Spacer()
            RoundGlyphButton(kind: .info) {
                withAnimation { viewModel.infoShowing = true }
            }
            RoundGlyphButton(kind: .close) { viewModel.cancel() }
        }
        .padding(.bottom, 18)
    }

    // MARK: Body

    private var body_: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "FORMAT").padding(.leading, 4).padding(.bottom, 7)
                SegmentedPicker(
                    options: [("JPEG", OutputFormat.jpeg), ("WebP", .webP), ("PNG", .png)],
                    selection: $viewModel.settings.format)
                Text(viewModel.formatHint)
                    .font(Theme.font(size: 11.5, .light))
                    .foregroundColor(Theme.textLo)
                    .padding(.leading, 6).padding(.top, 7).padding(.bottom, 18)

                SectionLabel(text: "QUALITY").padding(.leading, 4).padding(.bottom, 7)
                SegmentedPicker(
                    options: [("High", QualityPreset.high), ("Balanced", .balanced), ("Low", .smallest)],
                    selection: $viewModel.settings.preset)
                Text(viewModel.presetHint)
                    .font(Theme.font(size: 11.5, .light))
                    .foregroundColor(Theme.textLo)
                    .padding(.leading, 6).padding(.top, 7).padding(.bottom, 18)

                sizeSection

                SunkenPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep originals")
                                .font(Theme.font(size: 14.5, .semibold))
                                .foregroundColor(Theme.textHi)
                            Text(viewModel.keepHint)
                                .font(Theme.font(size: 11.5, .light))
                                .foregroundColor(Theme.textLo)
                        }
                        Spacer()
                        NeuToggle(isOn: $viewModel.settings.keepOriginals)
                    }
                }
                .padding(.bottom, 18)

                destinationSection

                if let validation = viewModel.validationText {
                    Text(validation)
                        .font(Theme.font(size: 12, .light))
                        .foregroundColor(Theme.danger)
                        .padding(.top, 10).padding(.leading, 6)
                }
            }
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "SIZE")
                Spacer()
                NeuToggle(isOn: $viewModel.settings.resizeEnabled)
            }
            .padding(.bottom, 4)

            ValueBubbleSlider(
                value: Binding(
                    get: { Double(max(viewModel.settings.boxWidth, viewModel.settings.boxHeight)) },
                    set: { newValue in
                        viewModel.settings.boxWidth = Int(newValue)
                        viewModel.settings.boxHeight = Int(newValue)
                    }),
                range: sizeRange)
                .padding(.horizontal, 14)
                .padding(.top, 46)
                .disabled(!viewModel.settings.resizeEnabled)
                .opacity(viewModel.settings.resizeEnabled ? 1 : 0.4)

            HStack {
                HStack(spacing: 8) {
                    NeuTextField(text: Binding(
                        get: { String(viewModel.settings.boxWidth) },
                        set: { if let v = Int($0) { viewModel.settings.boxWidth = v } }))
                        .frame(width: 66, height: 38)
                    Text("×").font(Theme.font(size: 15, .light)).foregroundColor(Theme.textLo)
                    NeuTextField(text: Binding(
                        get: { String(viewModel.settings.boxHeight) },
                        set: { if let v = Int($0) { viewModel.settings.boxHeight = v } }))
                        .frame(width: 66, height: 38)
                    Text("px").font(Theme.font(size: 13, .light)).foregroundColor(Theme.textLo)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach([500, 1080, 1920], id: \.self) { px in
                        Button("\(px)") {
                            viewModel.settings.boxWidth = px
                            viewModel.settings.boxHeight = px
                        }
                        .buttonStyle(ChipButtonStyle())
                    }
                }
            }
            .padding(.top, 16)
            .disabled(!viewModel.settings.resizeEnabled)
            .opacity(viewModel.settings.resizeEnabled ? 1 : 0.4)
        }
        .padding(.bottom, 18)
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "SAVE COPIES TO")
                .opacity(viewModel.settings.keepOriginals ? 1 : 0.45)
                .padding(.bottom, 7)
            SegmentedPicker(
                options: [("Subfolder", OutputLocationMode.subfolder), ("Suffix", .suffix), ("Folder…", .customFolder)],
                selection: $viewModel.settings.locationMode)
                .disabled(!viewModel.settings.keepOriginals)
                .opacity(viewModel.settings.keepOriginals ? 1 : 0.45)

            HStack(spacing: 10) {
                if viewModel.settings.keepOriginals && viewModel.settings.locationMode == .customFolder {
                    NeuTextField(text: .constant(viewModel.settings.customFolder), alignment: .leading,
                                 isReadOnly: true, font: Theme.font(size: 12.5, .regular))
                        .frame(height: 38)
                } else {
                    Text(viewModel.locationHint)
                        .font(Theme.font(size: 12.5, .light))
                        .foregroundColor(Theme.textLo)
                        .frame(height: 38, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    viewModel.pickCustomFolder()
                } label: {
                    Image(systemName: "folder")
                        .foregroundColor(Theme.textMid)
                }
                .buttonStyle(RoundIconButtonStyle())
                .disabled(!(viewModel.settings.keepOriginals && viewModel.settings.locationMode == .customFolder))
                .opacity(viewModel.settings.keepOriginals && viewModel.settings.locationMode == .customFolder ? 1 : 0.4)
            }
            .padding(.top, 10)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") { viewModel.cancel() }
                .buttonStyle(SoftButtonStyle())
                .frame(width: 120)
            Button("Compress") { viewModel.compress() }
                .buttonStyle(AccentButtonStyle())
                .disabled(viewModel.files.isEmpty)
                .opacity(viewModel.files.isEmpty ? 0.45 : 1)
        }
        .padding(.top, 20)
    }

    // MARK: Drop overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color(hex: 0xEDF3F8, opacity: 0.95))
            .padding(22)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: 0xE9F1FF))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Theme.accentBlue, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                    )
                    .padding(22)
            )
            .overlay(
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.accentBlue)
                    Text("Drop to add photos")
                        .font(Theme.font(size: 17, .regular))
                        .foregroundColor(Theme.accentBlue)
                    Text(dropSubText)
                        .font(Theme.font(size: 12, .light))
                        .foregroundColor(Theme.textMid)
                }
            )
            .allowsHitTesting(false)
    }

    private var dropSubText: String {
        switch viewModel.files.count {
        case 0: return "JPEG · PNG · WebP · HEIC · BMP · TIFF · GIF"
        case 1: return "They'll be added to the 1 photo already queued"
        default: return "They'll be added to the \(viewModel.files.count) photos already queued"
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        if viewModel.infoShowing { withAnimation { viewModel.infoShowing = false } }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, DroppedFiles.isSupported(path: url.path) || url.hasDirectoryPath else { return }
                DispatchQueue.main.async {
                    for path in DroppedFiles.collect(from: url) {
                        viewModel.addFile(path)
                    }
                }
            }
        }
    }
}

/// Direct port of DroppedFiles.cs.
enum DroppedFiles {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff", "gif", "heic", "heif"]

    static func isSupported(path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Files first, then the top level of any dropped folders — deliberately
    /// not recursive, so dropping a photo library doesn't silently queue
    /// thousands of files.
    static func collect(from url: URL) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if isDir.boolValue {
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            return children.map(\.path).filter(isSupported)
        }
        return isSupported(path: url.path) ? [url.path] : []
    }
}
