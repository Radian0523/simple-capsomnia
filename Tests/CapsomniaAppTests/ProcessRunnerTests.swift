@testable import Capsomnia
import XCTest

final class ProcessRunnerTests: XCTestCase {
    func testSynchronousRunCapturesOutputAndStatus() {
        let result = ProcessRunner().runSynchronously(
            executablePath: "/usr/bin/printf",
            arguments: ["capsomnia"]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.standardOutput, "capsomnia")
        XCTAssertEqual(result.standardError, "")
    }

    func testSynchronousRunReportsLaunchFailure() {
        let result = ProcessRunner().runSynchronously(
            executablePath: "/path/that/does/not/exist",
            arguments: []
        )

        XCTAssertEqual(result.status, -1)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertFalse(result.standardError.isEmpty)
    }
}
