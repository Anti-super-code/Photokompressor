import Foundation

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case jpeg, webP, png
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable {
    case high, balanced, smallest
}

public enum OutputLocationMode: String, Codable, CaseIterable, Sendable {
    case subfolder, suffix, customFolder
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var format: OutputFormat = .jpeg
    public var preset: QualityPreset = .balanced

    public var resizeEnabled: Bool = true
    public var boxWidth: Int = 1920
    public var boxHeight: Int = 1920

    public var keepOriginals: Bool = true

    /// Only applies when keepOriginals is true; replace mode always writes in place.
    public var locationMode: OutputLocationMode = .subfolder
    public var customFolder: String = ""

    /// macOS-only app preferences (no Windows equivalent — Topmost was
    /// always-on there; this exposes it as a user choice instead).
    public var alwaysOnTop: Bool = true
    public var autoOpenGallery: Bool = false

    public static let subfolderName = "Compressed"
    public static let suffixText = "-compressed"

    public init() {}

    // Custom decoding, deliberately: the synthesized Decodable throws on
    // any missing key, so every field added after a user's settings.json
    // was last written (alwaysOnTop/autoOpenGallery were added after
    // format/preset/etc.) would fail the *entire* decode and silently
    // reset every setting back to defaults, not just the new ones. Each
    // field falls back to AppSettings()'s own default when absent instead.
    private enum CodingKeys: String, CodingKey {
        case format, preset, resizeEnabled, boxWidth, boxHeight, keepOriginals
        case locationMode, customFolder, alwaysOnTop, autoOpenGallery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        format = try c.decodeIfPresent(OutputFormat.self, forKey: .format) ?? defaults.format
        preset = try c.decodeIfPresent(QualityPreset.self, forKey: .preset) ?? defaults.preset
        resizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .resizeEnabled) ?? defaults.resizeEnabled
        boxWidth = try c.decodeIfPresent(Int.self, forKey: .boxWidth) ?? defaults.boxWidth
        boxHeight = try c.decodeIfPresent(Int.self, forKey: .boxHeight) ?? defaults.boxHeight
        keepOriginals = try c.decodeIfPresent(Bool.self, forKey: .keepOriginals) ?? defaults.keepOriginals
        locationMode = try c.decodeIfPresent(OutputLocationMode.self, forKey: .locationMode) ?? defaults.locationMode
        customFolder = try c.decodeIfPresent(String.self, forKey: .customFolder) ?? defaults.customFolder
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? defaults.alwaysOnTop
        autoOpenGallery = try c.decodeIfPresent(Bool.self, forKey: .autoOpenGallery) ?? defaults.autoOpenGallery
    }

    public func extensionForFormat() -> String {
        switch format {
        case .jpeg: return ".jpg"
        case .webP: return ".webp"
        case .png: return ".png"
        }
    }
}
