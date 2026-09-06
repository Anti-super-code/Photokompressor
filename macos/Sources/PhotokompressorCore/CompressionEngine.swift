import Foundation
import CVips

/// Cancellation flag shared across a batch — the Swift equivalent of
/// CancellationToken, since Foundation has no built-in cooperative token.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private struct VipsOpError: Error { let message: String }

/// Direct port of CompressionEngine.cs: same libvips pipeline, same preset
/// numbers, same "keep original if the result isn't actually smaller", same
/// temp-file-then-atomic-promote write strategy. The two real platform
/// differences are HEIC decode (native ImageIO instead of Magick.NET, see
/// HeicDecoder.swift) and the replace-mode safety check (macOS Trash needs
/// no Windows-style volume/quota preflight, see Trash.swift).
public final class CompressionEngine: @unchecked Sendable {
    private let resolver = OutputPathResolver()

    /// Longest path the native codecs handle reliably; longer paths are bounced through NSTemporaryDirectory().
    private static let maxNativePathLength = 240
    /// WebP hard format limit per side.
    private static let webpMaxDimension: Int32 = 16383

    public init() {}

    public static func configureConcurrency(_ taskDegreeOfParallelism: Int) {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        cvips_set_concurrency(Int32(max(2, cores / max(1, taskDegreeOfParallelism))))
        // libvips' operation cache holds decoded images — and keeps their source files
        // open — which blocks trashing the original in replace mode. Every file is
        // read exactly once here, so the cache buys nothing and only costs us locks.
        cvips_set_cache_max(0)
    }

    public static var taskDegreeOfParallelism: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 1), 4)
    }

    public func runBatch(files: [String], settings: AppSettings, cancellation: CancellationFlag,
                          onResult: @escaping (CompressionResult) -> Void) {
        let frozen = settings
        let queue = DispatchQueue(label: "gr.antidot.photokompressor.compress", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: Self.taskDegreeOfParallelism)
        let group = DispatchGroup()

        for file in files {
            if cancellation.isCancelled {
                onResult(CompressionResult(inputPath: file, outputPath: nil, beforeBytes: 0, afterBytes: 0,
                                            status: .cancelled, note: nil))
                continue
            }
            semaphore.wait()
            group.enter()
            queue.async { [weak self] in
                defer { semaphore.signal(); group.leave() }
                guard let self else { return }
                if cancellation.isCancelled {
                    onResult(CompressionResult(inputPath: file, outputPath: nil, beforeBytes: 0, afterBytes: 0,
                                                status: .cancelled, note: nil))
                    return
                }
                onResult(self.compressFile(inputPath: file, settings: frozen))
            }
        }
        group.wait()
    }

    public func compressFile(inputPath: String, settings: AppSettings, forceEvenIfLarger: Bool = false) -> CompressionResult {
        let fm = FileManager.default
        var beforeBytes: Int64 = 0
        var tempPath: String?
        var cleanup: [String] = []

        do {
            guard let attrs = try? fm.attributesOfItem(atPath: inputPath),
                  let size = attrs[.size] as? Int64 else {
                return CompressionResult(inputPath: inputPath, outputPath: nil, beforeBytes: 0, afterBytes: 0,
                                          status: .failed, note: "File not found")
            }
            beforeBytes = size

            let finalPath = resolver.resolve(inputPath: inputPath, settings: settings)
            let destDir = (finalPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            let ext = settings.extensionForFormat()
            let guid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            let tp = (destDir as NSString).appendingPathComponent(".pk-tmp-\(guid)\(ext)")
            var nativeTempPath = tp
            if tp.utf8.count > Self.maxNativePathLength {
                nativeTempPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("pk-out-\(guid)\(ext)")
            }
            tempPath = tp

            var nativeInputPath = inputPath
            if inputPath.utf8.count > Self.maxNativePathLength {
                let inExt = (inputPath as NSString).pathExtension
                nativeInputPath = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("pk-in-\(guid).\(inExt)")
                try fm.copyItem(atPath: inputPath, toPath: nativeInputPath)
                cleanup.append(nativeInputPath)
            }

            var note: String?
            let image = try loadPipeline(path: nativeInputPath, settings: settings, note: &note)
            defer { VipsRuntime.unref(image) }
            try save(image: image, path: nativeTempPath, settings: settings)

            if nativeTempPath != tp {
                try fm.moveItem(atPath: nativeTempPath, toPath: tp)
            }

            let afterAttrs = try fm.attributesOfItem(atPath: tp)
            let afterBytes = (afterAttrs[.size] as? Int64) ?? 0
            if afterBytes <= 0 {
                throw VipsOpError(message: "Output file is empty.")
            }

            if afterBytes >= beforeBytes && !forceEvenIfLarger {
                try? fm.removeItem(atPath: tp)
                return CompressionResult(inputPath: inputPath, outputPath: nil, beforeBytes: beforeBytes,
                                          afterBytes: beforeBytes, status: .keptOriginal,
                                          note: "Already smaller — kept original")
            }

            if settings.keepOriginals {
                try fm.moveItem(atPath: tp, toPath: finalPath)
            } else {
                try Trash.promoteTempOverOriginal(tempPath: tp, originalPath: inputPath, finalPath: finalPath)
            }
            for path in cleanup { try? fm.removeItem(atPath: path) }
            return CompressionResult(inputPath: inputPath, outputPath: finalPath, beforeBytes: beforeBytes,
                                      afterBytes: afterBytes, status: .compressed, note: note)
        } catch {
            if let tp = tempPath { try? fm.removeItem(atPath: tp) }
            for path in cleanup { try? fm.removeItem(atPath: path) }
            return CompressionResult(inputPath: inputPath, outputPath: nil, beforeBytes: beforeBytes, afterBytes: 0,
                                      status: .failed, note: Self.friendlyError(error))
        }
    }

    // MARK: - Pipeline

    private func loadPipeline(path: String, settings: AppSettings, note: inout String?) throws -> VipsImageRef {
        note = nil
        // A huge box is a no-op resize (never upscales) that still gives us
        // auto-rotation and ICC handling from the same code path.
        let boxW: Int32 = settings.resizeEnabled ? Int32(settings.boxWidth) : 5_000_000
        let boxH: Int32 = settings.resizeEnabled ? Int32(settings.boxHeight) : 5_000_000

        var image: VipsImageRef
        if HeicDecoder.isHeic(path: path) {
            image = try loadViaImageIO(path: path, settings: settings, boxW: boxW, boxH: boxH)
        } else if let vipsLoaded = cvips_thumbnail_file(path, boxW, boxH) {
            image = vipsLoaded
        } else {
            // The bundled libvips doesn't cover every format (e.g. some BMP
            // variants); ImageIO reads far more, so give it a shot before failing.
            image = try loadViaImageIO(path: path, settings: settings, boxW: boxW, boxH: boxH)
        }

        let pages = cvips_get_n_pages(image)
        if pages > 1 {
            note = "Animated input — first frame only"
        }

        if settings.format == .webP {
            let w = cvips_image_get_width(image)
            let h = cvips_image_get_height(image)
            if w > Self.webpMaxDimension || h > Self.webpMaxDimension {
                guard let shrunk = cvips_thumbnail_image(image, Self.webpMaxDimension, Self.webpMaxDimension) else {
                    throw VipsOpError(message: VipsRuntime.lastError)
                }
                VipsRuntime.unref(image)
                image = shrunk
                note = note == nil ? "Reduced to WebP's 16383 px limit" : note! + "; reduced to WebP's 16383 px limit"
            }
        }
        return image
    }

    private func loadViaImageIO(path: String, settings: AppSettings, boxW: Int32, boxH: Int32) throws -> VipsImageRef {
        let full = try HeicDecoder.load(path: path)
        if !settings.resizeEnabled {
            return full
        }
        guard let resized = cvips_thumbnail_image(full, boxW, boxH) else {
            VipsRuntime.unref(full)
            throw VipsOpError(message: VipsRuntime.lastError)
        }
        VipsRuntime.unref(full)
        return resized
    }

    private func save(image: VipsImageRef, path: String, settings: AppSettings) throws {
        switch settings.format {
        case .jpeg:
            let p = Presets.jpeg(settings.preset)
            let hasAlpha = cvips_has_alpha(image) != 0
            let flat: VipsImageRef
            if hasAlpha {
                guard let flattened = cvips_flatten_white(image) else {
                    throw VipsOpError(message: VipsRuntime.lastError)
                }
                flat = flattened
            } else {
                flat = image
            }
            defer { if flat != image { VipsRuntime.unref(flat) } }

            let subsampleOn: Int32 = p.forceSubsampleOn ? 1 : 0
            if cvips_jpegsave_mozjpeg(flat, path, p.q, subsampleOn) != 0 {
                // Bundled libvips without mozjpeg support: retry with baseline flags.
                try? FileManager.default.removeItem(atPath: path)
                if cvips_jpegsave_baseline(flat, path, p.q, subsampleOn) != 0 {
                    throw VipsOpError(message: VipsRuntime.lastError)
                }
            }
        case .png:
            let p = Presets.png(settings.preset)
            let rc: Int32
            if p.palette {
                rc = cvips_pngsave_palette(image, path, p.q, p.dither, p.effort)
            } else {
                rc = cvips_pngsave_lossless(image, path)
            }
            if rc != 0 { throw VipsOpError(message: VipsRuntime.lastError) }
        case .webP:
            let p = Presets.webp(settings.preset)
            if cvips_webpsave(image, path, p.q, p.effort, p.alphaQ) != 0 {
                throw VipsOpError(message: VipsRuntime.lastError)
            }
        }
    }

    // MARK: - Errors

    private static func friendlyError(_ error: Error) -> String {
        if let vipsError = error as? VipsOpError {
            return vipsError.message.isEmpty ? "Couldn't read or convert this file" : vipsError.message
        }
        if let heicError = error as? HeicDecoder.HeicError {
            switch heicError {
            case .decodeFailed, .renderFailed: return "Couldn't read this file"
            case .vipsFailed: return "Couldn't convert this file"
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return "Access denied"
            case NSFileWriteOutOfSpaceError: return "Disk full"
            default: break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case Int(EACCES): return "Access denied"
            case Int(ENOSPC): return "Disk full"
            case Int(EBUSY), Int(ETXTBSY): return "File is in use by another program"
            default: break
            }
        }
        return nsError.localizedDescription
    }
}
