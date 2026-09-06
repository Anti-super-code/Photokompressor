import XCTest
@testable import PhotokompressorCore

final class FinderIntegrationTests: XCTestCase {
    private var scratchDir: URL!

    override func setUp() {
        super.setUp()
        // Point registration at a scratch directory instead of the real
        // ~/Library/Services — these tests used to operate on that real
        // path, meaning a run could delete whatever Quick Action
        // registration was actually live on the machine, and could also
        // fail depending on whatever real state happened to be there.
        scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotokompressorTests-\(UUID().uuidString)", isDirectory: true)
        FinderIntegration.servicesDirOverride = scratchDir
    }

    override func tearDown() {
        try? FinderIntegration.unregister()
        try? FileManager.default.removeItem(at: scratchDir)
        FinderIntegration.servicesDirOverride = nil
        super.tearDown()
    }

    /// Found via a real crash during hands-on testing: registering while
    /// running from the mounted install .dmg bakes in a /Volumes/... path
    /// that stops existing the moment the disk image is ejected.
    func testRefusesToRegisterFromRemovableVolume() {
        XCTAssertThrowsError(
            try FinderIntegration.register(appPathOverride: "/Volumes/Photokompressor 1.0.0/Photokompressor.app")
        ) { error in
            guard let finderError = error as? FinderIntegration.FinderIntegrationError else {
                return XCTFail("wrong error type: \(error)")
            }
            XCTAssertEqual(finderError, .runningFromRemovableVolume)
        }
        XCTAssertFalse(FinderIntegration.isRegistered())
    }

    func testRegistersFromANormalPath() throws {
        try FinderIntegration.register(appPathOverride: "/Applications/Photokompressor.app")
        XCTAssertTrue(FinderIntegration.isRegistered())
    }
}
