import Foundation

public enum SleepMode: String, Equatable, Sendable {
    case normalSleep
    case preventSleep

    public init(capsLockOn: Bool) {
        self = capsLockOn ? .preventSleep : .normalSleep
    }
}

public enum ControllerFailure: Equatable, Sendable {
    case helper(status: Int32, message: String)
    case stateUnavailable
    case stateMismatch(expected: SleepMode, actualDisabled: Bool)
}

public enum SleepControllerState: Equatable, Sendable {
    case stopped
    case synchronizing(desired: SleepMode, generation: UInt64)
    case verified(desired: SleepMode, verifiedAt: Date)
    case degraded(desired: SleepMode, failure: ControllerFailure, retryAt: Date)

    public var desiredMode: SleepMode? {
        switch self {
        case .stopped:
            nil
        case let .synchronizing(desired, _),
             let .verified(desired, _),
             let .degraded(desired, _, _):
            desired
        }
    }
}

