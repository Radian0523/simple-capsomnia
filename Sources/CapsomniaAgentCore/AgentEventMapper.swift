import CryptoKit
import Foundation

public enum AgentEventMapperError: Error, Equatable {
    case payloadTooLarge
    case invalidJSON
    case missingSessionID
}

public enum AgentEventMapper {
    public static let maximumPayloadSize = 1_048_576

    public static func record(
        provider: AgentProvider,
        payload: Data,
        now: Date = Date(),
        processIdentity: AgentProcessIdentity? = nil
    ) throws -> AgentActivityRecord? {
        guard payload.count <= maximumPayloadSize else {
            throw AgentEventMapperError.payloadTooLarge
        }
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              let dictionary = object as? [String: Any] else {
            throw AgentEventMapperError.invalidJSON
        }
        guard let sessionID = boundedString(dictionary["session_id"], maximumLength: 512),
              !sessionID.isEmpty else {
            throw AgentEventMapperError.missingSessionID
        }
        guard let eventName = boundedString(dictionary["hook_event_name"], maximumLength: 128),
              let phase = phase(provider: provider, eventName: eventName, payload: dictionary) else {
            return nil
        }

        let cwd = boundedString(dictionary["cwd"], maximumLength: 4_096) ?? ""
        let projectName = displayProjectName(cwd: cwd)

        return AgentActivityRecord(
            provider: provider,
            sessionIDHash: hash(sessionID),
            projectName: projectName,
            phase: phase,
            updatedAt: now,
            processIdentity: processIdentity
        )
    }

    private static func phase(
        provider: AgentProvider,
        eventName: String,
        payload: [String: Any]
    ) -> AgentActivityPhase? {
        switch eventName {
        case "SessionStart":
            return .ready
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PreCompact", "PostCompact", "SubagentStart", "SubagentStop",
             "TaskCreated", "TaskCompleted", "TeammateIdle":
            return .working
        case "PermissionRequest", "Elicitation":
            return .attention
        case "Stop":
            return .waiting
        case "StopFailure":
            return .failed
        case "SessionEnd":
            return .ended
        case "Notification" where provider == .claude:
            switch boundedString(payload["notification_type"], maximumLength: 128) {
            case "permission_prompt", "elicitation_dialog", "agent_needs_input":
                return .attention
            case "idle_prompt", "agent_completed":
                return .waiting
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func boundedString(_ value: Any?, maximumLength: Int) -> String? {
        guard let string = value as? String, string.count <= maximumLength else { return nil }
        return string
    }

    private static func displayProjectName(cwd: String) -> String {
        guard !cwd.isEmpty else { return "Unknown project" }
        let name = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
        return name.isEmpty ? "/" : String(name.prefix(120))
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
