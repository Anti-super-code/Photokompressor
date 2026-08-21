import Foundation
import AppKit
import PhotokompressorCore

/// Direct port of ProgressWindow.xaml.cs: runs the batch, updates per-file
/// rows and totals live, and drives the footer's cancel/back/open-folder
/// state machine.
@MainActor
final class ProgressViewModel: ObservableObject {
    @Published private(set) var items: [ResultRowItem] = []
    @Published private(set) var doneCount = 0
    @Published private(set) var finished = false
    @Published private(set) var cancelling = false
    @Published private(set) var totalsText = ""
    @Published private(set) var titleText = "COMPRESSING"
    /// >0 once the batch finishes with files that came out larger under the
    /// requested format and so were kept as-is — drives a one-time "convert
    /// anyway?" alert. Format-preserving recompresses that end up larger are
    /// left alone; only an actual filetype change is worth re-asking about.
    @Published private(set) var conversionPromptCount = 0

    private let files: [String]
    private let settings: AppSettings
    private let engine = CompressionEngine()
    private let cancellation = CancellationFlag()
    private var byPath: [String: ResultRowItem] = [:]
    private var totalBefore: Int64 = 0
    private var totalAfter: Int64 = 0
    private var firstOutputDir: String?
    private var conversionCandidates: [String] = []

    var onRequestClose: (() -> Void)?
    /// Distinct from onRequestClose: "Back" (only enabled once finished)
    /// should return to a fresh, empty Options dialog and close this
    /// window — not just close it, which (being the app's only window)
    /// would quit the whole app instead, same as "Done" is meant to.
    var onBack: (() -> Void)?

    var overallProgress: Double {
        files.isEmpty ? 0 : Double(doneCount) / Double(files.count)
    }

    var countText: String {
        finished ? "\(doneCount) of \(files.count) processed" : "\(doneCount) of \(files.count)…"
    }

    var canOpenOutputFolder: Bool { firstOutputDir != nil }

    init(files: [String], settings: AppSettings) {
        self.files = files
        self.settings = settings
        self.items = files.map { ResultRowItem(inputPath: $0) }
        for item in items { byPath[item.id] = item }
        updateTotals()
    }

    var conversionPromptFormatName: String {
        switch settings.format {
        case .jpeg: return "JPEG"
        case .webP: return "WebP"
        case .png: return "PNG"
        }
    }

    var conversionPromptMessage: String {
        let noun = conversionPromptCount == 1 ? "photo came" : "photos came"
        return "\(conversionPromptCount) \(noun) out larger as \(conversionPromptFormatName). "
            + "Convert them anyway and keep the new format?"
    }

    func start() {
        let engine = engine
        let filesCopy = files
        let settingsCopy = settings
        let cancellationRef = cancellation

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            engine.runBatch(files: filesCopy, settings: settingsCopy, cancellation: cancellationRef) { result in
                Task { @MainActor in
                    self?.handle(result)
                }
            }
            Task { @MainActor in
                self?.finish()
            }
        }
    }

    private func handle(_ result: CompressionResult) {
        guard let item = byPath[result.inputPath] else { return }
        doneCount += 1
        apply(result, to: item)
        updateTotals()
    }

    /// Shared with `convertKeptAnyway()`'s forced-retry results, which must
    /// update totals/badge the same way but must NOT double-count doneCount
    /// — that file was already counted done on the first pass.
    private func apply(_ result: CompressionResult, to item: ResultRowItem) {
        switch result.status {
        case .compressed:
            item.detail = "\(Self.formatSize(result.beforeBytes)) → \(Self.formatSize(result.afterBytes))"
                + (result.note.map { "  ·  \($0)" } ?? "")
            let pct = 100 - Int((100.0 * Double(result.afterBytes) / Double(result.beforeBytes)).rounded())
            item.badge = pct >= 0 ? "−\(pct)%" : "+\(-pct)%"
            item.kind = .done
            totalBefore += result.beforeBytes
            totalAfter += result.afterBytes
            if firstOutputDir == nil, let outputPath = result.outputPath {
                firstOutputDir = (outputPath as NSString).deletingLastPathComponent
            }
        case .keptOriginal:
            item.detail = result.note ?? "Already smaller — kept original"
            item.badge = "kept"
            item.kind = .kept
            if isFormatConversion(inputPath: result.inputPath) {
                conversionCandidates.append(result.inputPath)
            }
        case .cancelled:
            item.detail = "Cancelled"
            item.badge = "—"
            item.kind = .cancelled
        case .failed:
            item.detail = result.note ?? "Failed"
            item.badge = "failed"
            item.kind = .failed
        }
    }

    private func isFormatConversion(inputPath: String) -> Bool {
        var inputExt = (inputPath as NSString).pathExtension.lowercased()
        if inputExt == "jpeg" { inputExt = "jpg" }
        let targetExt = settings.extensionForFormat().dropFirst().lowercased()
        return inputExt != targetExt
    }

    /// User said yes to the "convert anyway?" prompt: re-run just the kept
    /// files, this time writing the result even though it's larger.
    func convertKeptAnyway() {
        guard !conversionCandidates.isEmpty else { return }
        let candidates = conversionCandidates
        let settingsCopy = settings
        let engine = engine
        conversionCandidates = []
        conversionPromptCount = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for path in candidates {
                let result = engine.compressFile(inputPath: path, settings: settingsCopy, forceEvenIfLarger: true)
                Task { @MainActor in
                    guard let self, let item = self.byPath[result.inputPath] else { return }
                    self.apply(result, to: item)
                    self.updateTotals()
                }
            }
        }
    }

    func dismissConversionPrompt() {
        conversionCandidates = []
        conversionPromptCount = 0
    }

    private func finish() {
        finished = true
        for item in items where item.kind == .pending {
            item.detail = "Cancelled"
            item.badge = "—"
            item.kind = .cancelled
        }
        titleText = "FINISHED"
        updateTotals()
        conversionPromptCount = conversionCandidates.count
    }

    private func updateTotals() {
        guard totalBefore > 0 else {
            totalsText = finished ? "Nothing to save here" : ""
            return
        }
        let pct = 100 - Int((100.0 * Double(totalAfter) / Double(totalBefore)).rounded())
        totalsText = "\(Self.formatSize(totalBefore)) → \(Self.formatSize(totalAfter))   −\(pct)%"
    }

    func cancel() {
        if finished {
            onRequestClose?()
            return
        }
        cancellation.cancel()
        cancelling = true
        titleText = "CANCELLING"
    }

    func openOutputFolder() {
        guard let dir = firstOutputDir else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    private static func formatSize(_ bytes: Int64) -> String {
        FileSizeFormatting.string(bytes)
    }
}
