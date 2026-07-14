@testable import Capsomnia
import CapsomniaCore
import Darwin
import XCTest

final class HelperVerifierTests: XCTestCase {
    func testAcceptsValidDevelopmentHelperWithoutTeamIdentifier() throws {
        let verifier = makeVerifier(
            signature: .init(identifier: identity.helperSigningIdentifier, teamIdentifier: nil)
        )
        XCTAssertNoThrow(try verifier.verify())
    }

    func testRejectsInvalidConfigurationBeforeReadingFile() {
        let verifier = HelperVerifier(
            identity: identity,
            configurationIsValid: false,
            expectedTeamIdentifier: nil,
            fileMetadataReader: FakeMetadataReader(values: [:]),
            signatureInspector: FakeSignatureInspector(result: .failure(.invalidSignature))
        )
        assertVerificationError(.invalidConfiguration, from: verifier)
    }

    func testRejectsMissingHelperBeforeSudoCanRun() {
        let verifier = HelperVerifier(
            identity: identity,
            configurationIsValid: true,
            expectedTeamIdentifier: nil,
            fileMetadataReader: FakeMetadataReader(values: [:]),
            signatureInspector: FakeSignatureInspector(result: .failure(.invalidSignature))
        )
        assertVerificationError(.missing, from: verifier)
    }

    func testRejectsSymlinkAndNonRegularFile() {
        assertVerificationError(.symbolicLink, from: makeVerifier(helperType: .symbolicLink))
        assertVerificationError(.notRegularFile, from: makeVerifier(helperType: .other))
    }

    func testRejectsWrongOwnerAndWritableModes() {
        assertVerificationError(.invalidOwner, from: makeVerifier(owner: 501))
        assertVerificationError(.invalidOwner, from: makeVerifier(group: 20))
        assertVerificationError(.writableByNonRoot, from: makeVerifier(mode: 0o775))
        assertVerificationError(.writableByNonRoot, from: makeVerifier(mode: 0o757))
    }

    func testRejectsNonExecutableAndUnsafeParent() {
        assertVerificationError(.notExecutable, from: makeVerifier(mode: 0o644))
        assertVerificationError(
            .invalidParentDirectory,
            from: makeVerifier(parentMode: 0o777)
        )
    }

    func testRejectsInvalidSignatureAndWrongIdentifier() {
        let invalidSignature = makeVerifier(signatureResult: .failure(.invalidSignature))
        assertVerificationError(.invalidSignature, from: invalidSignature)

        let wrongIdentifier = makeVerifier(signature: .init(
            identifier: "com.example.replaced-helper",
            teamIdentifier: nil
        ))
        assertVerificationError(.wrongSigningIdentifier, from: wrongIdentifier)
    }

    func testReleaseRequiresMatchingTeamIdentifier() throws {
        let releaseIdentity = try ProductIdentity(
            bundleIdentifier: ProductIdentity.canonicalBundleIdentifier,
            buildFlavor: .release
        )

        let missingTeam = makeVerifier(
            identity: releaseIdentity,
            expectedTeamIdentifier: "TEAM123456",
            signature: .init(
                identifier: releaseIdentity.helperSigningIdentifier,
                teamIdentifier: nil
            )
        )
        assertVerificationError(.missingTeamIdentifier, from: missingTeam)

        let wrongTeam = makeVerifier(
            identity: releaseIdentity,
            expectedTeamIdentifier: "TEAM123456",
            signature: .init(
                identifier: releaseIdentity.helperSigningIdentifier,
                teamIdentifier: "OTHERTEAM1"
            )
        )
        assertVerificationError(.wrongTeamIdentifier, from: wrongTeam)

        let valid = makeVerifier(
            identity: releaseIdentity,
            expectedTeamIdentifier: "TEAM123456",
            signature: .init(
                identifier: releaseIdentity.helperSigningIdentifier,
                teamIdentifier: "TEAM123456"
            )
        )
        XCTAssertNoThrow(try valid.verify())
    }

    private var identity: ProductIdentity {
        .development
    }

    private func makeVerifier(
        identity: ProductIdentity = .development,
        owner: uid_t = 0,
        group: gid_t = 0,
        mode: mode_t = 0o755,
        helperType: VerifiedFileType = .regular,
        parentMode: mode_t = 0o755,
        expectedTeamIdentifier: String? = nil,
        signature: CodeSignatureInformation? = nil,
        signatureResult: Result<CodeSignatureInformation, HelperVerificationError>? = nil
    ) -> HelperVerifier {
        let helperPath = identity.helperPath
        let parentPath = URL(fileURLWithPath: helperPath).deletingLastPathComponent().path
        let metadata = FakeMetadataReader(values: [
            helperPath: VerifiedFileMetadata(
                type: helperType,
                owner: owner,
                group: group,
                mode: mode
            ),
            parentPath: VerifiedFileMetadata(
                type: .directory,
                owner: 0,
                group: 0,
                mode: parentMode
            )
        ])
        let defaultSignature = CodeSignatureInformation(
            identifier: identity.helperSigningIdentifier,
            teamIdentifier: nil
        )
        let result = signatureResult ?? .success(signature ?? defaultSignature)

        return HelperVerifier(
            identity: identity,
            configurationIsValid: true,
            expectedTeamIdentifier: expectedTeamIdentifier,
            fileMetadataReader: metadata,
            signatureInspector: FakeSignatureInspector(result: result)
        )
    }

    private func assertVerificationError(
        _ expected: HelperVerificationError,
        from verifier: HelperVerifier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try verifier.verify(), file: file, line: line) { error in
            XCTAssertEqual(error as? HelperVerificationError, expected, file: file, line: line)
        }
    }
}

private struct FakeMetadataReader: FileMetadataReading {
    let values: [String: VerifiedFileMetadata]

    func metadata(at path: String) throws -> VerifiedFileMetadata {
        guard let value = values[path] else {
            throw HelperVerificationError.missing
        }
        return value
    }
}

private struct FakeSignatureInspector: CodeSignatureInspecting {
    let result: Result<CodeSignatureInformation, HelperVerificationError>

    func inspect(path: String) throws -> CodeSignatureInformation {
        try result.get()
    }
}
