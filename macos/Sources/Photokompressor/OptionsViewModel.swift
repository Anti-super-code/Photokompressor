import Foundation
import AppKit
import PhotokompressorCore

/// State and behavior for the main dialog — the Swift counterpart of
/// OptionsWindow.xaml.cs, minus the WPF-specific control wiring (that lives
/// in OptionsView's SwiftUI bindings instead).
@MainActor
final class OptionsViewModel: ObservableObject {
    @Published var files: [String] = []
    @Published var settings: AppSettings
    @Published private(set) var compressStarted = false
    @Published var infoShowing = false
    @Published var shellRegistered = FinderIntegration.isRegistered()
    @Published var shellHintOverride: String?
    @Published var validationText: String?
    @Published var dropHighlighted = false

    /// Set by AppCoordinator right after the window is created — lets this
    /// view model close its own window without knowing about AppKit.
    var onRequestClose: (() -> Void)?
    var onCompress: ((_ files: [String], _ settings: AppSettings) -> Void)?

    static let sourceURL = URL(string: "https://github.com/Anti-super-code/Photokompressor")!
    static let homepageURL = URL(string: "https://antidot.gr")!

    init(files: [String]) {
        self.files = files
        self.settings = SettingsStore.load()
    }

    var subtitleText: String {
        switch files.count {
        case 0: return "No photos selected — drop some here"
        case 1: return "1 photo selected"
        default: return "\(files.count) photos selected"
        }
    }

    var formatHint: String {
        switch settings.format {
        case .png: return "Lossless — much larger for photos, ideal for graphics"
        case .webP: return "Smallest files — great for web and storage"
        case .jpeg: return "Best all-round choice for photos"
        }
    }

    var presetHint: String {
        switch settings.preset {
        case .high: return "Barely any loss — larger files"
        case .smallest: return "Maximum savings — some softening"
        case .balanced: return "Recommended — big savings, no visible loss"
        }
    }

    var keepHint: String {
        settings.keepOriginals
            ? "Originals stay exactly where they are"
            // "Recoverable" oversold it: the Trash can be emptied, and it isn't a backup.
            : "Originals go to the Trash — keep a backup"
    }

    var locationHint: String {
        if !settings.keepOriginals { return "Compressed files take the originals' place" }
        switch settings.locationMode {
        case .suffix: return "Next to each original, named “photo-compressed.jpg”"
        default: return "A “Compressed” folder next to each original"
        }
    }

    var shellHint: String {
        if let override = shellHintOverride { return override }
        return shellRegistered
            ? "Compress straight from Finder — right-click any photo"
            : "Add it to compress without opening this window"
    }

    func addFile(_ path: String) {
        guard !compressStarted else { return }
        if !files.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            files.append(path)
        }
    }

    func deselectAll() {
        files.removeAll()
    }

    func toggleShellRegistration(_ enabled: Bool) {
        do {
            if enabled {
                try FinderIntegration.register()
            } else {
                try FinderIntegration.unregister()
            }
            shellHintOverride = nil
        } catch {
            shellRegistered = FinderIntegration.isRegistered()
            shellHintOverride = "Couldn't update it — \(error.localizedDescription)"
        }
    }

    func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose output folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !settings.customFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.customFolder)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.customFolder = url.path
            settings.locationMode = .customFolder
            validationText = nil
        }
    }

    func compress() {
        guard !files.isEmpty else { return }
        if settings.keepOriginals && settings.locationMode == .customFolder
            && settings.customFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationText = "Choose a destination folder first."
            pickCustomFolder()
            return
        }

        SettingsStore.save(settings)
        compressStarted = true
        onCompress?(files, settings)
        onRequestClose?()
    }

    func cancel() {
        onRequestClose?()
    }
}
