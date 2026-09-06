import Foundation

/// Direct port of SettingsStore.cs — same JSON-file-of-settings approach,
/// relocated to macOS's equivalent of %APPDATA%.
public enum SettingsStore {
    public static var settingsURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Photokompressor", isDirectory: true)
            .appendingPathComponent("settings.json")
    }()

    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        sanitize(&settings)
        return settings
    }

    public static func save(_ settings: AppSettings) {
        do {
            let dir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            // Settings persistence is best-effort; never block compression on it.
        }
    }

    private static func sanitize(_ settings: inout AppSettings) {
        settings.boxWidth = min(max(settings.boxWidth, 16), 65500)
        settings.boxHeight = min(max(settings.boxHeight, 16), 65500)
        if settings.locationMode == .customFolder
            && settings.customFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.locationMode = .subfolder
        }
    }
}
