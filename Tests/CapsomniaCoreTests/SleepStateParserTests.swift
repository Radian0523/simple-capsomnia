import CapsomniaCore
import XCTest

final class SleepStateParserTests: XCTestCase {
    func testParsesKnownValuesWithExtraWhitespace() {
        XCTAssertEqual(SleepStateParser.parse("  SleepDisabled    1  \n"), true)
        XCTAssertEqual(SleepStateParser.parse("System-wide settings:\nSleepDisabled\t0\n"), false)
    }

    func testRejectsMissingUnexpectedAndDuplicateValues() {
        XCTAssertNil(SleepStateParser.parse("System-wide settings:"))
        XCTAssertNil(SleepStateParser.parse("SleepDisabled 2"))
        XCTAssertNil(SleepStateParser.parse("SleepDisabled yes"))
        XCTAssertNil(SleepStateParser.parse("SleepDisabled 1\nSleepDisabled 1"))
        XCTAssertNil(SleepStateParser.parse(""))
    }
}

