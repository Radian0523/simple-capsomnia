import CapsomniaCore
import CapsomniaPmsetHelperCore
import Foundation
import XCTest

final class SleepControllerTests: XCTestCase {
    func testStartAppliesAndVerifiesCapsLockState() async {
        let reader = QueueStateReader([true])
        let helper = RecordingHelper()
        let now = Date(timeIntervalSince1970: 100)
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: true,
            now: now
        )

        let commands = await helper.recordedCommands()
        let state = await controller.currentState()
        XCTAssertEqual(commands, [.on])
        XCTAssertEqual(state, .verified(desired: .preventSleep, verifiedAt: now))
    }

    func testHelperSuccessDoesNotCountUntilStateMatches() async {
        let reader = QueueStateReader([false])
        let helper = RecordingHelper()
        let now = Date(timeIntervalSince1970: 200)
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: now
        )

        let state = await controller.currentState()
        XCTAssertEqual(state, .degraded(
            desired: .preventSleep,
            failure: .stateMismatch(expected: .preventSleep, actualDisabled: false),
            retryAt: now.addingTimeInterval(5)
        ))
    }

    func testRetriesHelperFailureOnlyAfterRetryDeadline() async {
        let reader = QueueStateReader([true])
        let helper = RecordingHelper(results: [
            .init(status: 1, standardError: "denied"),
            .success
        ])
        let start = Date(timeIntervalSince1970: 300)
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: start
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: start.addingTimeInterval(4.9)
        )
        let commandsBeforeDeadline = await helper.recordedCommands()
        XCTAssertEqual(commandsBeforeDeadline, [.on])

        await controller.update(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: start.addingTimeInterval(5)
        )
        let commandsAfterDeadline = await helper.recordedCommands()
        let state = await controller.currentState()
        XCTAssertEqual(commandsAfterDeadline, [.on, .on])
        XCTAssertEqual(
            state,
            .verified(desired: .preventSleep, verifiedAt: start.addingTimeInterval(5))
        )
    }

    func testPeriodicVerificationRepairsDrift() async {
        let reader = QueueStateReader([true, false, true])
        let helper = RecordingHelper()
        let start = Date(timeIntervalSince1970: 400)
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: start
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: false,
            now: start.addingTimeInterval(10)
        )

        let commands = await helper.recordedCommands()
        let state = await controller.currentState()
        XCTAssertEqual(commands, [.on, .on])
        XCTAssertEqual(
            state,
            .verified(desired: .preventSleep, verifiedAt: start.addingTimeInterval(10))
        )
    }

    func testStaleGenerationCannotOverwriteNewCapsLockState() async {
        let reader = QueueStateReader([false])
        let helper = ControlledHelper()
        let controller = SleepController(stateReader: reader, helper: helper)

        let first = Task {
            await controller.start(
                capsLockOn: true,
                lidClosed: false,
                displaySleepOnLidClose: false
            )
        }
        await helper.waitForCommandCount(1)

        let second = Task {
            await controller.update(
                capsLockOn: false,
                lidClosed: false,
                displaySleepOnLidClose: false
            )
        }
        await helper.waitForCommandCount(2)

        helper.complete(.off, with: .success)
        await second.value
        helper.complete(.on, with: .success)
        await first.value

        guard case .verified(desired: .normalSleep, _) = await controller.currentState() else {
            XCTFail("Expected the newest normal-sleep generation to remain verified")
            return
        }
    }

    func testDisplaySleepRunsOncePerClosedLidCycle() async {
        let reader = QueueStateReader([true])
        let helper = RecordingHelper()
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: true
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: true,
            displaySleepOnLidClose: true
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: true,
            displaySleepOnLidClose: true
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: false,
            displaySleepOnLidClose: true
        )
        await controller.update(
            capsLockOn: true,
            lidClosed: true,
            displaySleepOnLidClose: true
        )

        let commands = await helper.recordedCommands()
        XCTAssertEqual(commands, [.on, .displaySleep, .displaySleep])
    }

    func testUnknownLidStateDoesNotSleepDisplay() async {
        let reader = QueueStateReader([true])
        let helper = RecordingHelper()
        let controller = SleepController(stateReader: reader, helper: helper)

        await controller.start(
            capsLockOn: true,
            lidClosed: nil,
            displaySleepOnLidClose: true
        )

        let commands = await helper.recordedCommands()
        XCTAssertEqual(commands, [.on])
    }
}

private actor QueueStateReader: SleepStateReading {
    private var values: [Bool?]

    init(_ values: [Bool?]) {
        self.values = values
    }

    func readSleepDisabled() async -> Bool? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

private actor RecordingHelper: HelperRunning {
    private var commands: [HelperCommand] = []
    private var results: [OperationResult]

    init(results: [OperationResult] = []) {
        self.results = results
    }

    func run(_ command: HelperCommand) async -> OperationResult {
        commands.append(command)
        return results.isEmpty ? .success : results.removeFirst()
    }

    func recordedCommands() -> [HelperCommand] {
        commands
    }
}

private final class ControlledHelper: HelperRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [HelperCommand] = []
    private var continuations: [HelperCommand: [CheckedContinuation<OperationResult, Never>]] = [:]

    func run(_ command: HelperCommand) async -> OperationResult {
        await withCheckedContinuation { continuation in
            lock.withLock {
                commands.append(command)
                continuations[command, default: []].append(continuation)
            }
        }
    }

    func complete(_ command: HelperCommand, with result: OperationResult) {
        let continuation = lock.withLock {
            continuations[command]?.removeFirst()
        }
        continuation?.resume(returning: result)
    }

    func waitForCommandCount(_ count: Int) async {
        while true {
            let currentCount = lock.withLock { commands.count }
            if currentCount >= count { return }
            await Task.yield()
        }
    }
}
