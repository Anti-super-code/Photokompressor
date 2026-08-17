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

    private let files: [String]
    private let settings: AppSettings
    private let cancellation = CancellationFlag()
    private var byPath: [String: ResultRowItem] = [:]
    private var totalBefore: Int64 = 0
    private var totalAfter: Int64 = 0
    private var firstOutputDir: String?

    var onRequestClose: (() -> Void)?

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

    func start() {
        let engine = CompressionEngine()
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
        switch result.status {
        case .compressed:
            item.detail = "\(Self.formatSize(result.beforeBytes)) → \(Self.formatSize(result.afterBytes))"
                + (result.note.map { "  ·  \($0)" } ?? "")
            let pct = 100 - Int((100.0 * Double(result.afterBytes) / Double(result.beforeBytes)).rounded())
            item.badge = "−\(pct)%"
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
        case .cancelled:
            item.detail = "Cancelled"
            item.badge = "—"
            item.kind = .cancelled
        case .failed:
            item.detail = result.note ?? "Failed"
            item.badge = "failed"
            item.kind = .failed
        }
        updateTotals()
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
        switch bytes {
        case 1_048_576...: return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        case 1024...: return String(format: "%.0f KB", Double(bytes) / 1024.0)
        default: return "\(bytes) B"
        }
    }
}
