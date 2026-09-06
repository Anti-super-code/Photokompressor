import Foundation

/// macOS equivalent of SafeReplace.cs. Windows needs a volume/policy/quota
/// preflight before replace mode is allowed to run at all, because
/// FOF_ALLOWUNDO is only a request there and can silently hard-delete.
/// macOS's Trash has no such failure mode — FileManager.trashItem either
/// puts the file in the Trash or throws — so there's nothing to pre-check;
/// replace mode just attempts the move and reports failure like any other
/// I/O error.
public enum Trash {
    public enum TrashError: Error { case stillExists }

    /// Moves a finished temp file into its final place, trashing the original
    /// first. The original's extension may differ from the output's
    /// (heic -> jpg), so this can't use a same-name replace.
    public static func promoteTempOverOriginal(tempPath: String, originalPath: String, finalPath: String) throws {
        let fm = FileManager.default
        let originalURL = URL(fileURLWithPath: originalPath)
        try fm.trashItem(at: originalURL, resultingItemURL: nil)

        if fm.fileExists(atPath: originalPath) {
            throw TrashError.stillExists
        }
        try? fm.setAttributes([.immutable: false], ofItemAtPath: tempPath)
        try fm.moveItem(atPath: tempPath, toPath: finalPath)
    }
}
