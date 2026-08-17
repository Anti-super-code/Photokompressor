import XCTest
@testable import PhotokompressorCore

final class SettingsStoreTests: XCTestCase {
    private var originalURL: URL!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        originalURL = SettingsStore.settingsURL
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk-settings-tests-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
        SettingsStore.settingsURL = tempURL
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
        SettingsStore.settingsURL = originalURL
        super.tearDown()
    }

    func testLoadWithNoFileReturnsDefaults() {
        let s = SettingsStore.load()
        XCTAssertEqual(s, AppSettings())
    }

    func testSaveThenLoadRoundTrips() {
        var s = AppSettings()
        s.format = .webP
        s.preset = .high
        s.boxWidth = 1234
        s.boxHeight = 5678
        s.keepOriginals = false
        s.locationMode = .suffix
        SettingsStore.save(s)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.format, .webP)
        XCTAssertEqual(loaded.preset, .high)
        XCTAssertEqual(loaded.boxWidth, 1234)
        XCTAssertEqual(loaded.boxHeight, 5678)
        XCTAssertEqual(loaded.keepOriginals, false)
        XCTAssertEqual(loaded.locationMode, .suffix)
    }

    func testSanitizeClampsOutOfRangeBoxSize() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"format":"jpeg","preset":"balanced","resizeEnabled":true,"boxWidth":4,"boxHeight":999999,
         "keepOriginals":true,"locationMode":"subfolder","customFolder":""}
        """
        try json.data(using: .utf8)!.write(to: tempURL)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.boxWidth, 16)
        XCTAssertEqual(loaded.boxHeight, 65500)
    }

    func testSanitizeFallsBackFromEmptyCustomFolder() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"format":"jpeg","preset":"balanced","resizeEnabled":true,"boxWidth":1920,"boxHeight":1920,
         "keepOriginals":true,"locationMode":"customFolder","customFolder":"  "}
        """
        try json.data(using: .utf8)!.write(to: tempURL)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.locationMode, .subfolder)
    }

    /// Locks in the behavior added after a real bug: alwaysOnTop/
    /// autoOpenGallery were added to AppSettings after this shape of JSON
    /// (missing those two keys, as any settings.json saved before they
    /// existed would be) was already a plausible real file on disk.
    /// Missing keys must fall back individually to their own defaults, not
    /// fail the whole decode and silently reset every other saved setting.
    func testMissingNewerFieldsFallBackIndividually() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"format":"webP","preset":"high","resizeEnabled":true,"boxWidth":1234,"boxHeight":5678,
         "keepOriginals":false,"locationMode":"suffix","customFolder":""}
        """
        try json.data(using: .utf8)!.write(to: tempURL)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.format, .webP)
        XCTAssertEqual(loaded.boxWidth, 1234)
        XCTAssertEqual(loaded.keepOriginals, false)
        XCTAssertEqual(loaded.alwaysOnTop, AppSettings().alwaysOnTop)
        XCTAssertEqual(loaded.autoOpenGallery, AppSettings().autoOpenGallery)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: tempURL)
        XCTAssertEqual(SettingsStore.load(), AppSettings())
    }
}
