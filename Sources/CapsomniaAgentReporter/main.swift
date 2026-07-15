import CapsomniaAgentCore
import Darwin
import Foundation

private let arguments = CommandLine.arguments

private func reporterURL() -> URL {
    URL(fileURLWithPath: arguments[0]).standardizedFileURL
}

private func configurationManager() -> AgentHookConfigurationManager {
    AgentHookConfigurationManager(
        homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
        reporterURL: reporterURL()
    )
}

private func runEvent() {
    guard arguments.count == 6,
          arguments[2] == "--provider",
          let provider = AgentProvider(rawValue: arguments[3]),
          arguments[4] == "--protocol",
          arguments[5] == "capsomnia-agent-v1" else {
        exit(0)
    }

    let payload = FileHandle.standardInput.readDataToEndOfFile()
    do {
        let processIdentity = AgentProcessProbe.hookOwnerIdentity()
        guard let record = try AgentEventMapper.record(
            provider: provider,
            payload: payload,
            processIdentity: processIdentity
        ) else {
            exit(0)
        }
        let store = AgentActivityStore()
        if record.phase == .ended {
            try store.remove(record)
        } else {
            try store.write(record)
        }
    } catch {
        // Observability must never interrupt or alter an agent run.
    }
    exit(0)
}

private func runConfiguration(enabled: Bool) {
    do {
        try configurationManager().setEnabled(enabled)
        print(enabled ? "Agent hooks installed." : "Agent hooks removed.")
        exit(0)
    } catch {
        fputs("Could not update agent hook configuration: \(error)\n", stderr)
        exit(1)
    }
}

guard arguments.count >= 2 else {
    fputs("usage: CapsomniaAgentReporter event|install-hooks|remove-hooks|status\n", stderr)
    exit(64)
}

switch arguments[1] {
case "event":
    runEvent()
case "install-hooks":
    runConfiguration(enabled: true)
case "remove-hooks":
    runConfiguration(enabled: false)
case "status":
    print(configurationManager().isEnabled() ? "enabled" : "disabled")
default:
    fputs("usage: CapsomniaAgentReporter event|install-hooks|remove-hooks|status\n", stderr)
    exit(64)
}
