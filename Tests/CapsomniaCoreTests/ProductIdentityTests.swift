import CapsomniaCore
import XCTest

final class ProductIdentityTests: XCTestCase {
    func testDerivesEveryPrivilegedPathFromCanonicalBundleIdentifier() throws {
        let identity = try ProductIdentity(
            bundleIdentifier: "com.github.oonishidaichi.capsomnia",
            buildFlavor: .development
        )

        XCTAssertEqual(
            identity.helperSigningIdentifier,
            "com.github.oonishidaichi.capsomnia.pmset-helper"
        )
        XCTAssertEqual(
            identity.helperPath,
            "/Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper"
        )
        XCTAssertEqual(
            identity.sudoersPath,
            "/etc/sudoers.d/capsomnia_oonishidaichi"
        )
        XCTAssertFalse(identity.sudoersPath.split(separator: "/").last!.contains("."))
        XCTAssertEqual(
            identity.systemLaunchAgentPath,
            "/Library/LaunchAgents/com.github.oonishidaichi.capsomnia.plist"
        )
    }

    func testRejectsUnexpectedBundleIdentifierAndFlavor() {
        XCTAssertThrowsError(try ProductIdentity(
            bundleIdentifier: "com.example.capsomnia",
            buildFlavor: .development
        ))
        XCTAssertThrowsError(try ProductIdentity(
            bundleIdentifier: ProductIdentity.canonicalBundleIdentifier,
            buildFlavorRawValue: nil
        ))
        XCTAssertThrowsError(try ProductIdentity(
            bundleIdentifier: ProductIdentity.canonicalBundleIdentifier,
            buildFlavorRawValue: "debug"
        ))
    }
}
