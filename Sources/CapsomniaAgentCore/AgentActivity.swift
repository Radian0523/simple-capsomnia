import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

public enum AgentActivityPhase: String, Codable, Sendable {
    case ready
    case working
    case attention
    case waiting
    case failed
    case ended

    public var sortPriority: Int {
        switch self {
        case .attention: 0
        case .failed: 1
        case .working: 2
        case .waiting: 3
        case .ready: 4
        case .ended: 5
        }
    }
}

public struct AgentActivityRecord: Codable, Equatable, Identifiable, Sendable {
    public let provider: AgentProvider
    public let sessionIDHash: String
    public let projectName: String
    public let phase: AgentActivityPhase
    public let updatedAt: Date

    public init(
        provider: AgentProvider,
        sessionIDHash: String,
        projectName: String,
        phase: AgentActivityPhase,
        updatedAt: Date
    ) {
        self.provider = provider
        self.sessionIDHash = sessionIDHash
        self.projectName = projectName
        self.phase = phase
        self.updatedAt = updatedAt
    }

    public var id: String {
        "\(provider.rawValue)-\(sessionIDHash)"
    }

    public func isVisible(at date: Date) -> Bool {
        guard phase != .ended else { return false }
        let maximumAge: TimeInterval
        switch phase {
        case .working, .attention:
            maximumAge = 6 * 60 * 60
        case .ready, .waiting, .failed:
            maximumAge = 15 * 60
        case .ended:
            return false
        }
        return date.timeIntervalSince(updatedAt) <= maximumAge
    }
}

public extension Array where Element == AgentActivityRecord {
    func sortedForDisplay() -> [AgentActivityRecord] {
        sorted {
            if $0.phase.sortPriority != $1.phase.sortPriority {
                return $0.phase.sortPriority < $1.phase.sortPriority
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id < $1.id
        }
    }
}
