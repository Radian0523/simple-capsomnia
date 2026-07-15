import CapsomniaAgentCore
import Darwin
import Foundation
import XCTest

final class AgentActivityTests: XCTestCase {
    func testCodexLifecycleMapsWithoutPersistingSensitivePayload() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let processIdentity = AgentProcessIdentity(
            processIdentifier: 123,
            startTimeMicroseconds: 456
        )
        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": "session-secret",
            "cwd": "/Users/test/project-alpha",
            "hook_event_name": "UserPromptSubmit",
            "prompt": "do not persist this prompt",
            "error": "do not persist this error"
        ])

        let record = try XCTUnwrap(AgentEventMapper.record(
            provider: .codex,
            payload: payload,
            now: now,
            processIdentity: processIdentity
        ))

        XCTAssertEqual(record.provider, .codex)
        XCTAssertEqual(record.projectName, "project-alpha")
        XCTAssertEqual(record.phase, .working)
        XCTAssertEqual(record.updatedAt, now)
        XCTAssertEqual(record.processIdentity, processIdentity)
        XCTAssertNotEqual(record.sessionIDHash, "session-secret")
        XCTAssertEqual(record.sessionIDHash.count, 64)

        let encoded = try JSONEncoder().encode(record)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("do not persist"))
        XCTAssertFalse(text.contains("session-secret"))
    }

    func testAttentionCompletionFailureAndEndMappings() throws {
        XCTAssertEqual(try phase(.codex, event: "PermissionRequest"), .attention)
        XCTAssertEqual(try phase(.codex, event: "Stop"), .waiting)
        XCTAssertEqual(try phase(.claude, event: "StopFailure"), .failed)
        XCTAssertEqual(try phase(.claude, event: "SessionEnd"), .ended)
        XCTAssertEqual(
            try phase(
                .claude,
                event: "Notification",
                extra: ["notification_type": "idle_prompt"]
            ),
            .waiting
        )
        XCTAssertEqual(
            try phase(
                .claude,
                event: "Notification",
                extra: ["notification_type": "agent_completed"]
            ),
            .waiting
        )
        XCTAssertEqual(
            try phase(
                .claude,
                event: "Notification",
                extra: ["notification_type": "agent_needs_input"]
            ),
            .attention
        )
    }

    func testRejectsOversizedAndMissingSessionPayloads() throws {
        let oversized = Data(repeating: 0, count: AgentEventMapper.maximumPayloadSize + 1)
        XCTAssertThrowsError(try AgentEventMapper.record(provider: .codex, payload: oversized))

        let missing = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop"
        ])
        XCTAssertThrowsError(try AgentEventMapper.record(provider: .codex, payload: missing))
    }

    func testStoreLoadsVisibleRecordsAndRemovesExpiredRecords() throws {
        let directory = temporaryDirectory().appendingPathComponent("activity")
        let store = AgentActivityStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 20_000)
        let active = AgentActivityRecord(
            provider: .codex,
            sessionIDHash: String(repeating: "a", count: 64),
            projectName: "active",
            phase: .working,
            updatedAt: now
        )
        let expired = AgentActivityRecord(
            provider: .claude,
            sessionIDHash: String(repeating: "b", count: 64),
            projectName: "expired",
            phase: .waiting,
            updatedAt: now.addingTimeInterval(-901)
        )
        try store.write(active)
        try store.write(expired)

        XCTAssertEqual(try store.loadVisible(at: now), [active])
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions]
            as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o700)
    }

    func testStoreRemovesRecordWhenOriginalProcessEnds() throws {
        let directory = temporaryDirectory().appendingPathComponent("activity")
        let store = AgentActivityStore(directoryURL: directory)
        let identity = AgentProcessIdentity(
            processIdentifier: 123,
            startTimeMicroseconds: 456
        )
        let record = AgentActivityRecord(
            provider: .codex,
            sessionIDHash: String(repeating: "c", count: 64),
            projectName: "process-ended",
            phase: .working,
            updatedAt: Date(),
            processIdentity: identity
        )
        try store.write(record)

        XCTAssertEqual(
            try store.loadVisible(processIsRunning: { $0 == identity }),
            [record]
        )
        XCTAssertEqual(
            try store.loadVisible(processIsRunning: { _ in false }),
            []
        )
        XCTAssertEqual(try store.loadVisible(processIsRunning: { _ in true }), [])
    }

    func testWorkingRecordExpiresAfterTenMinutesWithoutEvents() throws {
        let directory = temporaryDirectory().appendingPathComponent("activity")
        let store = AgentActivityStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 30_000)
        let stale = AgentActivityRecord(
            provider: .claude,
            sessionIDHash: String(repeating: "d", count: 64),
            projectName: "stale-working",
            phase: .working,
            updatedAt: now.addingTimeInterval(-601)
        )
        try store.write(stale)

        XCTAssertEqual(try store.loadVisible(at: now), [])
    }

    func testProcessProbeRejectsPidReuse() throws {
        let identity = try XCTUnwrap(AgentProcessProbe.identity(processIdentifier: getpid()))
        XCTAssertTrue(AgentProcessProbe.isRunning(identity))

        let reused = AgentProcessIdentity(
            processIdentifier: identity.processIdentifier,
            startTimeMicroseconds: identity.startTimeMicroseconds + 1
        )
        XCTAssertFalse(AgentProcessProbe.isRunning(reused))
    }

    private func phase(
        _ provider: AgentProvider,
        event: String,
        extra: [String: Any] = [:]
    ) throws -> AgentActivityPhase? {
        var object: [String: Any] = [
            "session_id": "test-session",
            "cwd": "/tmp/project",
            "hook_event_name": event
        ]
        object.merge(extra) { _, new in new }
        let payload = try JSONSerialization.data(withJSONObject: object)
        return try AgentEventMapper.record(provider: provider, payload: payload)?.phase
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

final class AgentHookConfigurationManagerTests: XCTestCase {
    func testInstallIsIdempotentAndRemovalPreservesExistingHooks() throws {
        let root = temporaryDirectory()
        let codex = root.appendingPathComponent("codex/hooks.json")
        let claude = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(
            at: claude.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingCommand = "notify-existing"
        let existing: [String: Any] = [
            "permissions": ["allow": ["Read"]],
            "hooks": [
                "Notification": [[
                    "matcher": "idle_prompt",
                    "hooks": [["type": "command", "command": existingCommand]]
                ]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: claude)

        let manager = AgentHookConfigurationManager(
            codexHooksURL: codex,
            claudeSettingsURL: claude,
            reporterURL: URL(fileURLWithPath: "/Applications/Capsomnia Reporter")
        )
        try manager.setEnabled(true)
        try manager.setEnabled(true)

        XCTAssertTrue(manager.isEnabled())
        XCTAssertEqual(try capsomniaCommandCount(in: codex), 10)
        XCTAssertEqual(try capsomniaCommandCount(in: claude), 12)
        XCTAssertTrue(try fileContainsCommand(claude, command: existingCommand))

        try manager.setEnabled(false)

        XCTAssertFalse(manager.isEnabled())
        XCTAssertEqual(try capsomniaCommandCount(in: codex), 0)
        XCTAssertEqual(try capsomniaCommandCount(in: claude), 0)
        XCTAssertTrue(try fileContainsCommand(claude, command: existingCommand))
        let claudeRoot = try jsonRoot(claude)
        XCTAssertNotNil(claudeRoot["permissions"])
    }

    func testRefusesToReplaceMalformedHooksValue() throws {
        let malformedRoots: [[String: Any]] = [
            ["hooks": ["unexpected"]],
            ["hooks": ["Stop": "unexpected"]]
        ]
        for malformedRoot in malformedRoots {
            let root = temporaryDirectory()
            let codex = root.appendingPathComponent("codex/hooks.json")
            let claude = root.appendingPathComponent("claude/settings.json")
            try FileManager.default.createDirectory(
                at: codex.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let original = try JSONSerialization.data(withJSONObject: malformedRoot)
            try original.write(to: codex)

            let manager = AgentHookConfigurationManager(
                codexHooksURL: codex,
                claudeSettingsURL: claude,
                reporterURL: URL(fileURLWithPath: "/Applications/Capsomnia Reporter")
            )

            XCTAssertThrowsError(try manager.setEnabled(true))
            XCTAssertEqual(try Data(contentsOf: codex), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: claude.path))
        }
    }

    func testStatusRequiresEveryExpectedHook() throws {
        let root = temporaryDirectory()
        let codex = root.appendingPathComponent("codex/hooks.json")
        let claude = root.appendingPathComponent("claude/settings.json")
        let manager = AgentHookConfigurationManager(
            codexHooksURL: codex,
            claudeSettingsURL: claude,
            reporterURL: URL(fileURLWithPath: "/Applications/Capsomnia Reporter")
        )
        try manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled())

        var codexRoot = try jsonRoot(codex)
        var hooks = try XCTUnwrap(codexRoot["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "SessionStart")
        codexRoot["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: codexRoot).write(to: codex)

        XCTAssertFalse(manager.isEnabled())
    }

    private func capsomniaCommandCount(in url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        return text.components(separatedBy: AgentHookConfigurationManager.protocolMarker).count - 1
    }

    private func fileContainsCommand(_ url: URL, command: String) throws -> Bool {
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8)?.contains(command) == true
    }

    private func jsonRoot(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

final class CodexHooksListResponseParserTests: XCTestCase {
    func testReportsApprovalRequiredForUntrustedCapsomniaHook() throws {
        let data = try responseData(statuses: ["untrusted", "trusted"])

        XCTAssertEqual(
            CodexHooksListResponseParser.trustState(from: data),
            .approvalRequired
        )
    }

    func testReportsModifiedBeforeOtherStatuses() throws {
        let data = try responseData(statuses: ["trusted", "modified"])

        XCTAssertEqual(CodexHooksListResponseParser.trustState(from: data), .modified)
    }

    func testReportsTrustedForTrustedAndManagedHooks() throws {
        let data = try responseData(statuses: ["trusted", "managed"])

        XCTAssertEqual(CodexHooksListResponseParser.trustState(from: data), .trusted)
    }

    func testIgnoresUnrelatedHooks() throws {
        let root: [String: Any] = [
            "id": 2,
            "result": [
                "data": [[
                    "hooks": [[
                        "command": "echo unrelated",
                        "trustStatus": "untrusted"
                    ]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: root)

        XCTAssertEqual(CodexHooksListResponseParser.trustState(from: data), .notConfigured)
    }

    private func responseData(statuses: [String]) throws -> Data {
        let hooks = statuses.map { status in
            [
                "command": "CapsomniaAgentReporter event \(AgentHookConfigurationManager.protocolMarker)",
                "trustStatus": status
            ]
        }
        let root: [String: Any] = [
            "id": 2,
            "result": ["data": [["hooks": hooks]]]
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }
}
