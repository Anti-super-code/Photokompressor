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

    func testCorruptFileFallsBackToDefaults() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: tempURL)
        XCTAssertEqual(SettingsStore.load(), AppSettings())
    }
}
