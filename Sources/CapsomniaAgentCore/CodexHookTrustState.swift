import Foundation

public enum CodexHookTrustState: Equatable, Sendable {
    case checking
    case notConfigured
    case approvalRequired
    case modified
    case trusted
    case unavailable
}

public enum CodexHooksListResponseParser {
    public static func trustState(
        from data: Data,
        commandMarker: String = AgentHookConfigurationManager.protocolMarker
    ) -> CodexHookTrustState? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let entries = result["data"] as? [[String: Any]] else {
            return nil
        }

        let hooks = entries.flatMap { entry -> [[String: Any]] in
            entry["hooks"] as? [[String: Any]] ?? []
        }.filter { hook in
            (hook["command"] as? String)?.contains(commandMarker) == true
        }

        guard !hooks.isEmpty else { return .notConfigured }
        let statuses = hooks.compactMap { $0["trustStatus"] as? String }
        guard statuses.count == hooks.count else { return .unavailable }
        if statuses.contains("modified") {
            return .modified
        }
        if statuses.contains("untrusted") {
            return .approvalRequired
        }
        if statuses.allSatisfy({ $0 == "trusted" || $0 == "managed" }) {
            return .trusted
        }
        return .unavailable
    }
}
