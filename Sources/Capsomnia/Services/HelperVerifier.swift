import CapsomniaCore
import Darwin
import Foundation
import Security

enum HelperVerificationError: String, Error, Sendable {
    case invalidConfiguration = "invalid_configuration"
    case missing = "helper_missing"
    case symbolicLink = "helper_is_symlink"
    case notRegularFile = "helper_not_regular_file"
    case invalidOwner = "helper_invalid_owner"
    case writableByNonRoot = "helper_writable_by_non_root"
    case notExecutable = "helper_not_executable"
    case invalidParentDirectory = "helper_invalid_parent_directory"
    case invalidSignature = "helper_invalid_signature"
    case wrongSigningIdentifier = "helper_wrong_signing_identifier"
    case missingTeamIdentifier = "helper_missing_team_identifier"
    case wrongTeamIdentifier = "helper_wrong_team_identifier"
}

struct CodeSignatureInformation: Sendable {
    let identifier: String
    let teamIdentifier: String?
}

protocol CodeSignatureInspecting: Sendable {
    func inspect(path: String) throws -> CodeSignatureInformation
}

struct SystemCodeSignatureInspector: CodeSignatureInspecting {
    func inspect(path: String) throws -> CodeSignatureInformation {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(rawValue: 0),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw HelperVerificationError.invalidSignature
        }

        let validationFlags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate
        )
        guard SecStaticCodeCheckValidity(staticCode, validationFlags, nil) == errSecSuccess else {
            throw HelperVerificationError.invalidSignature
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard infoStatus == errSecSuccess,
              let dictionary = information as? [String: Any],
              let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String else {
            throw HelperVerificationError.invalidSignature
        }

        return CodeSignatureInformation(
            identifier: identifier,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}

enum VerifiedFileType: Sendable {
    case regular
    case directory
    case symbolicLink
    case other
}

struct VerifiedFileMetadata: Sendable {
    let type: VerifiedFileType
    let owner: uid_t
    let group: gid_t
    let mode: mode_t
}

protocol FileMetadataReading: Sendable {
    func metadata(at path: String) throws -> VerifiedFileMetadata
}

struct SystemFileMetadataReader: FileMetadataReading {
    func metadata(at path: String) throws -> VerifiedFileMetadata {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw HelperVerificationError.missing
        }

        let fileType: VerifiedFileType
        switch info.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFREG): fileType = .regular
        case mode_t(S_IFDIR): fileType = .directory
        case mode_t(S_IFLNK): fileType = .symbolicLink
        default: fileType = .other
        }

        return VerifiedFileMetadata(
            type: fileType,
            owner: info.st_uid,
            group: info.st_gid,
            mode: info.st_mode
        )
    }
}

struct HelperVerifier: Sendable {
    let identity: ProductIdentity
    let configurationIsValid: Bool
    let expectedTeamIdentifier: String?
    private let fileMetadataReader: any FileMetadataReading
    private let signatureInspector: any CodeSignatureInspecting

    init(
        identity: ProductIdentity,
        configurationIsValid: Bool,
        expectedTeamIdentifier: String?,
        fileMetadataReader: any FileMetadataReading = SystemFileMetadataReader(),
        signatureInspector: any CodeSignatureInspecting = SystemCodeSignatureInspector()
    ) {
        self.identity = identity
        self.configurationIsValid = configurationIsValid
        self.expectedTeamIdentifier = expectedTeamIdentifier
        self.fileMetadataReader = fileMetadataReader
        self.signatureInspector = signatureInspector
    }

    func verify() throws {
        guard configurationIsValid else {
            throw HelperVerificationError.invalidConfiguration
        }

        let fileInfo = try fileMetadataReader.metadata(at: identity.helperPath)
        guard fileInfo.type != .symbolicLink else {
            throw HelperVerificationError.symbolicLink
        }
        guard fileInfo.type == .regular else {
            throw HelperVerificationError.notRegularFile
        }
        guard fileInfo.owner == 0, fileInfo.group == 0 else {
            throw HelperVerificationError.invalidOwner
        }
        guard (fileInfo.mode & mode_t(S_IWGRP | S_IWOTH)) == 0 else {
            throw HelperVerificationError.writableByNonRoot
        }
        guard (fileInfo.mode & mode_t(S_IXUSR | S_IXGRP | S_IXOTH)) != 0 else {
            throw HelperVerificationError.notExecutable
        }

        try verifyParentDirectory()

        let signing = try signatureInspector.inspect(path: identity.helperPath)
        guard signing.identifier == identity.helperSigningIdentifier else {
            throw HelperVerificationError.wrongSigningIdentifier
        }

        if identity.buildFlavor == .release {
            guard let expectedTeamIdentifier, !expectedTeamIdentifier.isEmpty,
                  let helperTeamIdentifier = signing.teamIdentifier,
                  !helperTeamIdentifier.isEmpty else {
                throw HelperVerificationError.missingTeamIdentifier
            }
            guard helperTeamIdentifier == expectedTeamIdentifier else {
                throw HelperVerificationError.wrongTeamIdentifier
            }
        }
    }

    private func verifyParentDirectory() throws {
        let parent = URL(fileURLWithPath: identity.helperPath)
            .deletingLastPathComponent()
            .path
        let parentInfo: VerifiedFileMetadata
        do {
            parentInfo = try fileMetadataReader.metadata(at: parent)
        } catch {
            throw HelperVerificationError.invalidParentDirectory
        }
        guard parentInfo.type == .directory,
              parentInfo.owner == 0,
              parentInfo.group == 0,
              (parentInfo.mode & mode_t(S_IWGRP | S_IWOTH)) == 0 else {
            throw HelperVerificationError.invalidParentDirectory
        }
    }
}
