import CapsomniaCore
import CapsomniaPmsetHelperCore
import Darwin
import Foundation

final class HelperClient: HelperRunning, @unchecked Sendable {
    private let identity: ProductIdentity
    private let verifier: HelperVerifier
    private let runner: ProcessRunner

    init(configuration: AppConfiguration, runner: ProcessRunner) {
        identity = configuration.identity
        let signatureInspector = SystemCodeSignatureInspector()
        let appTeamIdentifier = try? signatureInspector
            .inspect(path: Bundle.main.bundleURL.path)
            .teamIdentifier
        verifier = HelperVerifier(
            identity: configuration.identity,
            configurationIsValid: configuration.permitsHelperExecution,
            expectedTeamIdentifier: appTeamIdentifier ?? nil,
            signatureInspector: signatureInspector
        )
        self.runner = runner
    }

    func run(_ command: HelperCommand) async -> OperationResult {
        if let verificationFailure = verificationFailure() {
            return verificationFailure
        }

        let result = await runner.run(
            executablePath: "/usr/bin/sudo",
            arguments: ["-n", identity.helperPath, command.rawValue]
        )
        return operationResult(from: result)
    }

    func runSynchronously(_ command: HelperCommand) -> OperationResult {
        if let verificationFailure = verificationFailure() {
            return verificationFailure
        }

        let result = runner.runSynchronously(
            executablePath: "/usr/bin/sudo",
            arguments: ["-n", identity.helperPath, command.rawValue]
        )
        return operationResult(from: result)
    }

    private func verificationFailure() -> OperationResult? {
        do {
            try verifier.verify()
        } catch let error as HelperVerificationError {
            return OperationResult(status: EX_CONFIG, standardError: error.rawValue)
        } catch {
            return OperationResult(status: EX_CONFIG, standardError: "helper_verification_failed")
        }
        return nil
    }

    private func operationResult(from result: ProcessExecutionResult) -> OperationResult {
        return OperationResult(
            status: result.status,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
    }
}
