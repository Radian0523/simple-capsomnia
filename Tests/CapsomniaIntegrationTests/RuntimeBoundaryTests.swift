import CapsomniaCore
import CapsomniaPmsetHelperCore
import XCTest

final class RuntimeBoundaryTests: XCTestCase {
    func testPrivilegedSurfaceIsExactlyThreeCommandsAtOneFixedPath() {
        let identity = ProductIdentity.development

        XCTAssertEqual(HelperCommand.allCases.count, 3)
        XCTAssertEqual(
            identity.helperPath,
            "/Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper"
        )
        XCTAssertEqual(Set(HelperCommand.allCases.map(\.rawValue)), [
            "on", "off", "display-sleep"
        ])
    }
}

