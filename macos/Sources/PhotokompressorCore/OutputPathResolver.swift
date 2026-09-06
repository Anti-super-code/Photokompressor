import Foundation

/// Resolves the final destination path for a compressed file, including collision
/// numbering that is safe under parallel batches (two inputs like a.png and a.jpg
/// can both map to a.jpg). Direct port of OutputPathResolver.cs.
public final class OutputPathResolver {
    private var reserved = Set<String>()
    private let lock = NSLock()

    public init() {}

    /// When keepOriginals is false the output goes next to the original with the
    /// original base name (in-place replace); location mode is ignored.
    public func resolve(inputPath: String, settings: AppSettings) -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let inputDir = inputURL.deletingLastPathComponent().path
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = settings.extensionForFormat()

        let dir: String
        let name: String
        if !settings.keepOriginals {
            dir = inputDir
            name = baseName
        } else {
            switch settings.locationMode {
            case .subfolder:
                dir = (inputDir as NSString).appendingPathComponent(AppSettings.subfolderName)
                name = baseName
            case .suffix:
                dir = inputDir
                name = baseName + AppSettings.suffixText
            case .customFolder:
                dir = settings.customFolder
                name = baseName
            }
        }

        lock.lock()
        defer { lock.unlock() }

        var candidate = (dir as NSString).appendingPathComponent(name + ext)
        var counter = 1
        while isTaken(candidate, inputPath: inputPath, settings: settings) {
            candidate = (dir as NSString).appendingPathComponent("\(name) (\(counter))\(ext)")
            counter += 1
        }
        reserved.insert(candidate.lowercased())
        return candidate
    }

    private func isTaken(_ candidate: String, inputPath: String, settings: AppSettings) -> Bool {
        if reserved.contains(candidate.lowercased()) { return true }
        // In replace mode the original file itself will be trashed, so landing on
        // the input path (e.g. photo.jpg -> photo.jpg) is not a collision.
        if !settings.keepOriginals && candidate.caseInsensitiveCompare(inputPath) == .orderedSame {
            return false
        }
        return FileManager.default.fileExists(atPath: candidate)
    }
}
