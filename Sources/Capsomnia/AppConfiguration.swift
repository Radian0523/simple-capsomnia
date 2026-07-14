import CapsomniaCore
import Foundation

struct AppConfiguration {
    let identity: ProductIdentity
    let permitsHelperExecution: Bool
    let errorDescription: String?

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            return AppConfiguration(
                identity: .development,
                permitsHelperExecution: true,
                errorDescription: nil
            )
        }

        do {
            let flavor = bundle.object(forInfoDictionaryKey: "CapsomniaBuildFlavor") as? String
            return AppConfiguration(
                identity: try ProductIdentity(
                    bundleIdentifier: bundleIdentifier,
                    buildFlavorRawValue: flavor
                ),
                permitsHelperExecution: true,
                errorDescription: nil
            )
        } catch {
            return AppConfiguration(
                identity: .development,
                permitsHelperExecution: false,
                errorDescription: "invalid_app_configuration"
            )
        }
    }
}

