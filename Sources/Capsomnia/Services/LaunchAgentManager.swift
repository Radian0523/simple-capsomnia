import CapsomniaCore
import Foundation

final class LaunchAgentManager: @unchecked Sendable {
    private let identity: ProductIdentity
    private let runner: ProcessRunner

    init(identity: ProductIdentity, runner: ProcessRunner) {
        self.identity = identity
        self.runner = runner
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        let userAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(identity.bundleIdentifier).plist")
            .path
        let hasInstalledAgent = FileManager.default.fileExists(atPath: userAgentPath)
            || FileManager.default.fileExists(atPath: identity.systemLaunchAgentPath)
        guard hasInstalledAgent else {
            return true
        }

        let result = await runner.run(
            executablePath: "/bin/launchctl",
            arguments: [
                enabled ? "enable" : "disable",
                "gui/\(getuid())/\(identity.bundleIdentifier)"
            ]
        )
        return result.status == 0
    }
}

