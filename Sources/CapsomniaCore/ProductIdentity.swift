import Foundation

public enum BuildFlavor: String, Equatable, Sendable {
    case development
    case release
}

public enum ProductIdentityError: Error, Equatable {
    case unexpectedBundleIdentifier(String)
    case invalidBuildFlavor(String?)
}

public struct ProductIdentity: Equatable, Sendable {
    public static let canonicalBundleIdentifier = "com.github.oonishidaichi.capsomnia"
    public static let sudoersFileName = "capsomnia_oonishidaichi"

    public let bundleIdentifier: String
    public let buildFlavor: BuildFlavor

    public init(bundleIdentifier: String, buildFlavor: BuildFlavor) throws {
        guard bundleIdentifier == Self.canonicalBundleIdentifier else {
            throw ProductIdentityError.unexpectedBundleIdentifier(bundleIdentifier)
        }
        self.bundleIdentifier = bundleIdentifier
        self.buildFlavor = buildFlavor
    }

    public init(bundleIdentifier: String, buildFlavorRawValue: String?) throws {
        guard let rawValue = buildFlavorRawValue,
              let flavor = BuildFlavor(rawValue: rawValue) else {
            throw ProductIdentityError.invalidBuildFlavor(buildFlavorRawValue)
        }
        try self.init(bundleIdentifier: bundleIdentifier, buildFlavor: flavor)
    }

    public static var development: ProductIdentity {
        try! ProductIdentity(
            bundleIdentifier: canonicalBundleIdentifier,
            buildFlavor: .development
        )
    }

    public var helperSigningIdentifier: String {
        "\(bundleIdentifier).pmset-helper"
    }

    public var helperPath: String {
        "/Library/PrivilegedHelperTools/\(helperSigningIdentifier)"
    }

    public var sudoersPath: String {
        "/etc/sudoers.d/\(Self.sudoersFileName)"
    }

    public var systemLaunchAgentPath: String {
        "/Library/LaunchAgents/\(bundleIdentifier).plist"
    }
}
