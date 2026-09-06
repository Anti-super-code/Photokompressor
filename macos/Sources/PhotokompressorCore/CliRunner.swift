import Foundation

/// Hidden headless mode so the engine can be exercised and tested without UI,
/// mirroring CliRunner.cs's flags exactly:
///   photokompressor-cli file... [--format jpeg|webp|png] [--preset high|balanced|smallest]
///                       [--fit WxH] [--replace] [--suffix] [--outdir path] [--report results.json]
public enum CliRunner {
    public static func run(_ args: [String]) -> Int32 {
        var files: [String] = []
        var settings = AppSettings()
        settings.resizeEnabled = false
        var reportPath: String?

        var i = 0
        func next() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            switch args[i] {
            case "--format":
                guard let v = next(), let fmt = parseFormat(v) else {
                    FileHandle.standardError.write("Bad arguments: unknown format\n".data(using: .utf8)!)
                    return 2
                }
                settings.format = fmt
            case "--preset":
                guard let v = next(), let preset = parsePreset(v) else {
                    FileHandle.standardError.write("Bad arguments: unknown preset\n".data(using: .utf8)!)
                    return 2
                }
                settings.preset = preset
            case "--fit":
                guard let v = next() else {
                    FileHandle.standardError.write("Bad arguments: --fit needs WxH\n".data(using: .utf8)!)
                    return 2
                }
                let parts = v.lowercased().split(separator: "x")
                guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else {
                    FileHandle.standardError.write("Bad arguments: --fit needs WxH\n".data(using: .utf8)!)
                    return 2
                }
                settings.resizeEnabled = true
                settings.boxWidth = w
                settings.boxHeight = h
            case "--replace":
                settings.keepOriginals = false
            case "--suffix":
                settings.locationMode = .suffix
            case "--outdir":
                guard let v = next() else {
                    FileHandle.standardError.write("Bad arguments: --outdir needs a path\n".data(using: .utf8)!)
                    return 2
                }
                settings.locationMode = .customFolder
                settings.customFolder = (v as NSString).standardizingPath
            case "--report":
                guard let v = next() else {
                    FileHandle.standardError.write("Bad arguments: --report needs a path\n".data(using: .utf8)!)
                    return 2
                }
                reportPath = (v as NSString).standardizingPath
            default:
                files.append(((args[i] as NSString).standardizingPath))
            }
            i += 1
        }

        CompressionEngine.configureConcurrency(1)
        let engine = CompressionEngine()
        var results: [CompressionResult] = []
        for file in files {
            let r = engine.compressFile(inputPath: file, settings: settings)
            results.append(r)
            let note = r.note.map { " [\($0)]" } ?? ""
            print("\(r.status.rawValue): \(r.inputPath) -> \(r.outputPath ?? "-") "
                  + "(\(r.beforeBytes) -> \(r.afterBytes) bytes)\(note)")
        }

        if let reportPath {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(results) {
                try? data.write(to: URL(fileURLWithPath: reportPath))
            }
        }

        return results.contains(where: { $0.status == .failed }) ? 1 : 0
    }

    /// The smallest preset is labelled "Low" in the UI; accept either name.
    private static func parsePreset(_ value: String) -> QualityPreset? {
        switch value.lowercased() {
        case "low", "smallest": return .smallest
        case "high": return .high
        case "balanced": return .balanced
        default: return nil
        }
    }

    private static func parseFormat(_ value: String) -> OutputFormat? {
        switch value.lowercased() {
        case "jpeg", "jpg": return .jpeg
        case "webp": return .webP
        case "png": return .png
        default: return nil
        }
    }
}
