import Foundation

public enum OutputFormat: String, Codable, CaseIterable {
    case jpeg, webP, png
}

public enum QualityPreset: String, Codable, CaseIterable {
    case high, balanced, smallest
}

public enum OutputLocationMode: String, Codable, CaseIterable {
    case subfolder, suffix, customFolder
}

public struct AppSettings: Codable, Equatable {
    public var format: OutputFormat = .jpeg
    public var preset: QualityPreset = .balanced

    public var resizeEnabled: Bool = true
    public var boxWidth: Int = 1920
    public var boxHeight: Int = 1920

    public var keepOriginals: Bool = true

    /// Only applies when keepOriginals is true; replace mode always writes in place.
    public var locationMode: OutputLocationMode = .subfolder
    public var customFolder: String = ""

    public static let subfolderName = "Compressed"
    public static let suffixText = "-compressed"

    public init() {}

    public func extensionForFormat() -> String {
        switch format {
        case .jpeg: return ".jpg"
        case .webP: return ".webp"
        case .png: return ".png"
        }
    }
}
