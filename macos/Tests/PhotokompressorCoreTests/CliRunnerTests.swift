import XCTest
@testable import PhotokompressorCore

final class CliRunnerTests: XCTestCase {
    func testUnknownFormatIsRejected() {
        XCTAssertEqual(CliRunner.run(["photo.jpg", "--format", "gif"]), 2)
    }

    func testUnknownPresetIsRejected() {
        XCTAssertEqual(CliRunner.run(["photo.jpg", "--preset", "ultra"]), 2)
    }

    func testMalformedFitIsRejected() {
        XCTAssertEqual(CliRunner.run(["photo.jpg", "--fit", "not-a-size"]), 2)
    }

    func testLowIsAcceptedAsAliasForSmallest() {
        // "Low" is the on-screen label for QualityPreset.smallest; the CLI accepts
        // either name. A missing input file still exercises the parser fully and
        // fails fast without touching the compression engine's happy path.
        XCTAssertEqual(CliRunner.run(["/nonexistent/photo.jpg", "--preset", "low"]), 1)
    }

    func testMissingFileReportsFailureAndWritesReport() throws {
        let reportPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk-cli-report-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: reportPath) }

        let exitCode = CliRunner.run(["/nonexistent/photo.jpg", "--report", reportPath])
        XCTAssertEqual(exitCode, 1)

        let data = try Data(contentsOf: URL(fileURLWithPath: reportPath))
        let results = try JSONDecoder().decode([CompressionResult].self, from: data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].note, "File not found")
    }
}
