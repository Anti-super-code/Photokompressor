import XCTest
@testable import PhotokompressorCore

final class OutputPathResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk-resolver-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func settings(keep: Bool = true, location: OutputLocationMode = .subfolder,
                           customFolder: String = "", format: OutputFormat = .jpeg) -> AppSettings {
        var s = AppSettings()
        s.keepOriginals = keep
        s.locationMode = location
        s.customFolder = customFolder
        s.format = format
        return s
    }

    func testSubfolderMode() {
        let resolver = OutputPathResolver()
        let input = tempDir.appendingPathComponent("photo.jpg").path
        let result = resolver.resolve(inputPath: input, settings: settings())
        XCTAssertEqual(result, tempDir.appendingPathComponent("Compressed/photo.jpg").path)
    }

    func testSuffixMode() {
        let resolver = OutputPathResolver()
        let input = tempDir.appendingPathComponent("photo.jpg").path
        let result = resolver.resolve(inputPath: input, settings: settings(location: .suffix))
        XCTAssertEqual(result, tempDir.appendingPathComponent("photo-compressed.jpg").path)
    }

    func testCustomFolderMode() {
        let resolver = OutputPathResolver()
        let input = tempDir.appendingPathComponent("photo.jpg").path
        let customDir = tempDir.appendingPathComponent("out").path
        let result = resolver.resolve(inputPath: input, settings: settings(location: .customFolder, customFolder: customDir))
        XCTAssertEqual(result, (customDir as NSString).appendingPathComponent("photo.jpg"))
    }

    func testReplaceModeIgnoresLocationMode() {
        let resolver = OutputPathResolver()
        let input = tempDir.appendingPathComponent("photo.heic").path
        let result = resolver.resolve(inputPath: input, settings: settings(keep: false, location: .subfolder, format: .jpeg))
        // Replace mode always writes next to the original with the original base name.
        XCTAssertEqual(result, tempDir.appendingPathComponent("photo.jpg").path)
    }

    func testCollisionNumberingAcrossDifferentInputExtensions() {
        let resolver = OutputPathResolver()
        let dir = tempDir!
        let jpgInput = dir.appendingPathComponent("a.jpg").path
        let pngInput = dir.appendingPathComponent("a.png").path

        let s = settings(keep: false) // replace mode: both map toward "a.jpg" in the same dir
        let first = resolver.resolve(inputPath: jpgInput, settings: s)
        let second = resolver.resolve(inputPath: pngInput, settings: s)

        XCTAssertEqual(first, dir.appendingPathComponent("a.jpg").path)
        // a.jpg is reserved by the first resolve (and isn't pngInput itself), so the
        // second must be numbered rather than silently colliding.
        XCTAssertEqual(second, dir.appendingPathComponent("a (1).jpg").path)
    }

    func testReplaceModeDoesNotTreatOwnInputAsCollision() {
        let resolver = OutputPathResolver()
        let input = tempDir.appendingPathComponent("a.jpg").path
        let result = resolver.resolve(inputPath: input, settings: settings(keep: false))
        // photo.jpg -> photo.jpg in replace mode is not a collision with itself.
        XCTAssertEqual(result, input)
    }

    func testCollisionWithExistingFileOnDisk() throws {
        let resolver = OutputPathResolver()
        let outDir = tempDir.appendingPathComponent("Compressed")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let existing = outDir.appendingPathComponent("photo.jpg")
        try Data().write(to: existing)

        let input = tempDir.appendingPathComponent("photo.jpg").path
        let result = resolver.resolve(inputPath: input, settings: settings())
        XCTAssertEqual(result, outDir.appendingPathComponent("photo (1).jpg").path)
    }
}
