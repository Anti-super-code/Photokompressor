import XCTest
@testable import PhotokompressorCore

final class FinderIntegrationTests: XCTestCase {
    override func tearDown() {
        try? FinderIntegration.unregister()
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
