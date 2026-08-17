import AppKit
import PhotokompressorCore

/// Owns window lifecycle for the whole app — the Swift counterpart of
/// App.xaml.cs. macOS's app model removes two whole pieces of that file:
/// there's no SingleInstance mutex/pipe (LSMultipleInstancesProhibited plus
/// `application(_:open:)` gives us that for free — a second `open -a
/// Photokompressor` just re-delivers to this instance), and there's no
/// per-process-per-file Explorer quirk to debounce around in the same way
/// since our Finder Quick Action hands over every selected file in one call.
/// The debounce is kept anyway: dropping files onto the app icon while it's
/// already busy, or several quick Quick Action invocations, can still arrive
/// as separate calls in quick succession.
@MainActor
final class AppCoordinator {
    private static let debounceInterval: TimeInterval = 0.3
    private static let debounceHardCap: TimeInterval = 2.0

    private var pendingFiles: [String] = []
    private var firstArrivalAt: Date?
    private var debounceTimer: Timer?
    private var shownAnything = false

    private weak var openOptionsViewModel: OptionsViewModel?
    private var galleryWindow: GalleryTrayWindow?

    func applicationDidFinishLaunching() {
        CompressionEngine.configureConcurrency(CompressionEngine.taskDegreeOfParallelism)
        // If this launch is carrying files, `application(_:open:)` typically
        // fires before this method returns; give it a brief moment to land
        // before falling back to an empty window for a plain launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showEmptyIfNothingHappenedYet()
        }
    }

    func handleOpenFiles(_ paths: [String]) {
        for path in paths {
            addPendingFile(path)
        }
    }

    /// Reopen/reactivate — the counterpart of the pipe's "--focus" token,
    /// sent by macOS when the already-running app is launched again with no
    /// files (icon click, `open -a Photokompressor` with no args).
    func focusOrShowEmpty() {
        if let window = NSApp.windows.last(where: { $0.isVisible }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        showOptions(files: [])
    }

    private func addPendingFile(_ path: String) {
        if let vm = openOptionsViewModel, !vm.compressStarted {
            vm.addFile(path)
            return
        }

        if pendingFiles.isEmpty { firstArrivalAt = Date() }
        if !pendingFiles.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            pendingFiles.append(path)
        }

        if let first = firstArrivalAt, Date().timeIntervalSince(first) >= Self.debounceHardCap {
            flushPending()
            return
        }

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flushPending() }
        }
    }

    private func flushPending() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard !pendingFiles.isEmpty else { return }
        showOptions(files: pendingFiles)
        pendingFiles.removeAll()
    }

    private func showEmptyIfNothingHappenedYet() {
        guard !shownAnything, pendingFiles.isEmpty else { return }
        showOptions(files: [])
    }

    func showOptions(files: [String]) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        shownAnything = true

        let debugFiles = ProcessInfo.processInfo.environment["PK_DEBUG_GALLERY"]?
            .split(separator: ",").map(String.init)
        let viewModel = OptionsViewModel(files: debugFiles ?? files)
        openOptionsViewModel = viewModel

        let window = ChromelessWindow(width: 500, height: 824, shadowMargin: 18,
                                       alwaysOnTop: viewModel.settings.alwaysOnTop) {
            OptionsView(viewModel: viewModel)
        }
        viewModel.onRequestClose = { [weak self, weak window] in
            self?.galleryWindow?.close()
            self?.galleryWindow = nil
            window?.close()
        }
        viewModel.onCompress = { [weak self] files, settings in
            self?.showProgress(files: files, settings: settings)
        }
        viewModel.onGalleryToggle = { [weak self, weak window, weak viewModel] showing in
            guard let self, let window else { return }
            if showing {
                guard let viewModel else { return }
                self.galleryWindow = GalleryTrayWindow(attachedTo: window) {
                    GalleryTrayView(viewModel: viewModel, onClose: { [weak viewModel] in
                        viewModel?.toggleGallery()
                    })
                }
            } else {
                self.galleryWindow?.close()
                self.galleryWindow = nil
            }
        }
        viewModel.onAlwaysOnTopChanged = { [weak window] alwaysOnTop in
            window?.setAlwaysOnTop(alwaysOnTop)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["PK_DEBUG_GALLERY"] != nil || viewModel.settings.autoOpenGallery {
            if !viewModel.files.isEmpty { viewModel.toggleGallery() }
        }
        if ProcessInfo.processInfo.environment["PK_DEBUG_OPTIONS"] != nil {
            viewModel.infoShowing = true
        }
    }

    func showProgress(files: [String], settings: AppSettings) {
        shownAnything = true
        let viewModel = ProgressViewModel(files: files, settings: settings)
        let window = ChromelessWindow(width: 596, height: 656, shadowMargin: 18,
                                       alwaysOnTop: settings.alwaysOnTop) {
            ProgressView(viewModel: viewModel)
        }
        viewModel.onRequestClose = { [weak window] in window?.close() }
        viewModel.onBack = { [weak self, weak window] in
            self?.showOptions(files: [])
            window?.close()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
