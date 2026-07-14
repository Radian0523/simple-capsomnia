import CapsomniaPmsetHelperCore
import Foundation

public struct OperationResult: Equatable, Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    public init(status: Int32, standardOutput: String = "", standardError: String = "") {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public static let success = OperationResult(status: 0)
}

public protocol SleepStateReading: Sendable {
    func readSleepDisabled() async -> Bool?
}

public protocol HelperRunning: Sendable {
    func run(_ command: HelperCommand) async -> OperationResult
}

