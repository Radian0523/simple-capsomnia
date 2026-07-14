import CapsomniaPmsetHelperCore
import Foundation

public actor SleepController {
    public typealias StateHandler = @Sendable (SleepControllerState) -> Void

    private let stateReader: any SleepStateReading
    private let helper: any HelperRunning
    private let stateHandler: StateHandler
    private let retryInterval: TimeInterval
    private let verificationInterval: TimeInterval

    private var state: SleepControllerState = .stopped
    private var desired: SleepMode?
    private var generation: UInt64 = 0
    private var nextVerificationAt = Date.distantPast
    private var didRequestDisplaySleep = false
    private var displayRequestGeneration: UInt64?
    private var nextDisplayRetryAt = Date.distantPast

    public init(
        stateReader: any SleepStateReading,
        helper: any HelperRunning,
        retryInterval: TimeInterval = 5,
        verificationInterval: TimeInterval = 10,
        stateHandler: @escaping StateHandler = { _ in }
    ) {
        self.stateReader = stateReader
        self.helper = helper
        self.retryInterval = retryInterval
        self.verificationInterval = verificationInterval
        self.stateHandler = stateHandler
    }

    public func currentState() -> SleepControllerState {
        state
    }

    public func start(
        capsLockOn: Bool,
        lidClosed: Bool?,
        displaySleepOnLidClose: Bool,
        now: Date = Date()
    ) async {
        desired = SleepMode(capsLockOn: capsLockOn)
        await synchronize(now: now)
        await evaluateDisplaySleep(
            lidClosed: lidClosed,
            enabled: displaySleepOnLidClose,
            now: now
        )
    }

    public func update(
        capsLockOn: Bool,
        lidClosed: Bool?,
        displaySleepOnLidClose: Bool,
        now: Date = Date()
    ) async {
        let newDesired = SleepMode(capsLockOn: capsLockOn)

        if desired != newDesired {
            desired = newDesired
            resetDisplaySleepCycle()
            await synchronize(now: now)
        } else {
            switch state {
            case .stopped:
                desired = newDesired
                await synchronize(now: now)
            case .synchronizing:
                break
            case let .degraded(_, _, retryAt) where now >= retryAt:
                await synchronize(now: now)
            case .verified where now >= nextVerificationAt:
                await verify(now: now)
            default:
                break
            }
        }

        await evaluateDisplaySleep(
            lidClosed: lidClosed,
            enabled: displaySleepOnLidClose,
            now: now
        )
    }

    public func retryNow(now: Date = Date()) async {
        guard desired != nil else { return }
        await synchronize(now: now)
    }

    @discardableResult
    public func stop() async -> OperationResult {
        generation &+= 1
        desired = nil
        resetDisplaySleepCycle()
        setState(.stopped)
        return await helper.run(.off)
    }

    private func synchronize(now: Date) async {
        guard let expected = desired else { return }
        generation &+= 1
        let operationGeneration = generation
        setState(.synchronizing(desired: expected, generation: operationGeneration))

        let command: HelperCommand = expected == .preventSleep ? .on : .off
        let result = await helper.run(command)
        guard operationGeneration == generation, desired == expected else { return }

        guard result.status == 0 else {
            let message = sanitizedMessage(result.standardError, fallback: result.standardOutput)
            degrade(
                expected,
                failure: .helper(status: result.status, message: message),
                now: now
            )
            return
        }

        await confirm(expected: expected, generation: operationGeneration, now: now)
    }

    private func verify(now: Date) async {
        guard let expected = desired else { return }
        let operationGeneration = generation
        let actual = await stateReader.readSleepDisabled()
        guard operationGeneration == generation, desired == expected else { return }

        guard let actual else {
            degrade(expected, failure: .stateUnavailable, now: now)
            return
        }

        if actual == (expected == .preventSleep) {
            markVerified(expected, now: now)
        } else {
            setState(.degraded(
                desired: expected,
                failure: .stateMismatch(expected: expected, actualDisabled: actual),
                retryAt: now
            ))
            await synchronize(now: now)
        }
    }

    private func confirm(expected: SleepMode, generation operationGeneration: UInt64, now: Date) async {
        let actual = await stateReader.readSleepDisabled()
        guard operationGeneration == generation, desired == expected else { return }

        guard let actual else {
            degrade(expected, failure: .stateUnavailable, now: now)
            return
        }

        guard actual == (expected == .preventSleep) else {
            degrade(
                expected,
                failure: .stateMismatch(expected: expected, actualDisabled: actual),
                now: now
            )
            return
        }

        markVerified(expected, now: now)
    }

    private func evaluateDisplaySleep(lidClosed: Bool?, enabled: Bool, now: Date) async {
        guard enabled,
              desired == .preventSleep,
              case .verified(desired: .preventSleep, _) = state else {
            if !enabled || desired != .preventSleep {
                resetDisplaySleepCycle()
            }
            return
        }

        guard let lidClosed else { return }
        guard lidClosed else {
            resetDisplaySleepCycle()
            return
        }
        guard !didRequestDisplaySleep,
              displayRequestGeneration == nil,
              now >= nextDisplayRetryAt else { return }

        let operationGeneration = generation
        displayRequestGeneration = operationGeneration
        let result = await helper.run(.displaySleep)
        guard displayRequestGeneration == operationGeneration else { return }
        displayRequestGeneration = nil

        guard operationGeneration == generation,
              desired == .preventSleep else { return }

        if result.status == 0 {
            didRequestDisplaySleep = true
            nextDisplayRetryAt = .distantPast
        } else {
            nextDisplayRetryAt = now.addingTimeInterval(retryInterval)
        }
    }

    private func markVerified(_ expected: SleepMode, now: Date) {
        nextVerificationAt = now.addingTimeInterval(verificationInterval)
        setState(.verified(desired: expected, verifiedAt: now))
    }

    private func degrade(_ expected: SleepMode, failure: ControllerFailure, now: Date) {
        setState(.degraded(
            desired: expected,
            failure: failure,
            retryAt: now.addingTimeInterval(retryInterval)
        ))
    }

    private func resetDisplaySleepCycle() {
        didRequestDisplaySleep = false
        displayRequestGeneration = nil
        nextDisplayRetryAt = .distantPast
    }

    private func setState(_ newState: SleepControllerState) {
        state = newState
        stateHandler(newState)
    }

    private func sanitizedMessage(_ primary: String, fallback: String) -> String {
        let value = primary.isEmpty ? fallback : primary
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars.prefix(2_048) {
            if !CharacterSet.controlCharacters.contains(scalar)
                || scalar == "\n"
                || scalar == "\t" {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
