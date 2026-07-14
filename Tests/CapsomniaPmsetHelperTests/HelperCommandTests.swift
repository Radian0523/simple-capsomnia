import CapsomniaPmsetHelperCore
import XCTest

final class HelperCommandTests: XCTestCase {
    func testAcceptsOnlyOneKnownArgument() {
        XCTAssertEqual(HelperCommand(arguments: ["on"]), .on)
        XCTAssertEqual(HelperCommand(arguments: ["off"]), .off)
        XCTAssertEqual(HelperCommand(arguments: ["display-sleep"]), .displaySleep)
        XCTAssertNil(HelperCommand(arguments: []))
        XCTAssertNil(HelperCommand(arguments: ["on", "off"]))
        XCTAssertNil(HelperCommand(arguments: ["invalid"]))
    }

    func testMapsCommandsToFixedPmsetArguments() {
        XCTAssertEqual(HelperCommand.on.pmsetArguments, ["-a", "disablesleep", "1"])
        XCTAssertEqual(HelperCommand.off.pmsetArguments, ["-a", "disablesleep", "0"])
        XCTAssertEqual(HelperCommand.displaySleep.pmsetArguments, ["displaysleepnow"])
    }
}

