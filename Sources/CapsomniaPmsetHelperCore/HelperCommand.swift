import Foundation

public enum HelperCommand: String, CaseIterable, Sendable {
    case on
    case off
    case displaySleep = "display-sleep"

    public init?(arguments: [String]) {
        guard arguments.count == 1, let command = Self(rawValue: arguments[0]) else {
            return nil
        }
        self = command
    }

    public var pmsetArguments: [String] {
        switch self {
        case .on:
            ["-a", "disablesleep", "1"]
        case .off:
            ["-a", "disablesleep", "0"]
        case .displaySleep:
            ["displaysleepnow"]
        }
    }
}

