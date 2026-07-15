import Foundation

public enum AgentHookConfigurationError: Error {
    case invalidConfiguration(URL)
    case unsafeConfiguration(URL)
}

public struct AgentHookConfigurationManager: Sendable {
    public static let protocolMarker = "--protocol capsomnia-agent-v1"

    public let codexHooksURL: URL
    public let claudeSettingsURL: URL
    public let reporterURL: URL

    public init(homeDirectoryURL: URL, reporterURL: URL) {
        self.init(
            codexHooksURL: homeDirectoryURL
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json"),
            claudeSettingsURL: homeDirectoryURL
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json"),
            reporterURL: reporterURL
        )
    }

    public init(codexHooksURL: URL, claudeSettingsURL: URL, reporterURL: URL) {
        self.codexHooksURL = codexHooksURL
        self.claudeSettingsURL = claudeSettingsURL
        self.reporterURL = reporterURL
    }

    public func setEnabled(_ enabled: Bool, fileManager: FileManager = .default) throws {
        var codex = try loadDocument(at: codexHooksURL, fileManager: fileManager)
        var claude = try loadDocument(at: claudeSettingsURL, fileManager: fileManager)
        codex.root = update(root: codex.root, provider: .codex, enabled: enabled)
        claude.root = update(root: claude.root, provider: .claude, enabled: enabled)

        do {
            try write(codex, fileManager: fileManager)
            try write(claude, fileManager: fileManager)
        } catch {
            try? restore(codex, fileManager: fileManager)
            try? restore(claude, fileManager: fileManager)
            throw error
        }
    }

    public func isEnabled(fileManager: FileManager = .default) -> Bool {
        guard let codex = try? loadDocument(at: codexHooksURL, fileManager: fileManager),
              let claude = try? loadDocument(at: claudeSettingsURL, fileManager: fileManager) else {
            return false
        }
        return containsCapsomniaHooks(codex.root, provider: .codex)
            && containsCapsomniaHooks(claude.root, provider: .claude)
    }

    private func update(
        root: [String: Any],
        provider: AgentProvider,
        enabled: Bool
    ) -> [String: Any] {
        var result = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [Any] else { continue }
            let filtered = groups.compactMap { group -> Any? in
                guard var dictionary = group as? [String: Any],
                      let handlers = dictionary["hooks"] as? [Any] else { return group }
                let remaining = handlers.filter { handler in
                    guard let handlerDictionary = handler as? [String: Any],
                          let command = handlerDictionary["command"] as? String else { return true }
                    return !command.contains(Self.protocolMarker)
                }
                guard !remaining.isEmpty else { return nil }
                dictionary["hooks"] = remaining
                return dictionary
            }
            if filtered.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = filtered
            }
        }

        if enabled {
            let command = hookCommand(provider: provider)
            for event in hookEvents(provider: provider) {
                var groups = hooks[event] as? [Any] ?? []
                groups.append([
                    "hooks": [[
                        "type": "command",
                        "command": command,
                        "timeout": 5
                    ]]
                ])
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    private func hookEvents(provider: AgentProvider) -> [String] {
        switch provider {
        case .codex:
            [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PostToolUse", "PreCompact", "PostCompact", "SubagentStart",
                "SubagentStop", "Stop"
            ]
        case .claude:
            [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart",
                "SubagentStop", "Stop", "StopFailure", "SessionEnd"
            ]
        }
    }

    private func hookCommand(provider: AgentProvider) -> String {
        "\(shellQuote(reporterURL.path)) event --provider \(provider.rawValue) "
            + Self.protocolMarker
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func containsCapsomniaHooks(
        _ root: [String: Any],
        provider: AgentProvider
    ) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        let expectedCommand = hookCommand(provider: provider)
        return hookEvents(provider: provider).allSatisfy { event in
            guard let value = hooks[event] else { return false }
            guard let groups = value as? [Any] else { return false }
            return groups.contains { group in
                guard let dictionary = group as? [String: Any],
                      let handlers = dictionary["hooks"] as? [Any] else { return false }
                return handlers.contains { handler in
                    guard let handlerDictionary = handler as? [String: Any],
                          let command = handlerDictionary["command"] as? String else { return false }
                    return command == expectedCommand
                }
            }
        }
    }

    private struct Document {
        let url: URL
        let originalData: Data?
        let originalMode: NSNumber?
        var root: [String: Any]
    }

    private func loadDocument(at url: URL, fileManager: FileManager) throws -> Document {
        let exists = fileManager.fileExists(atPath: url.path)
        if exists {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw AgentHookConfigurationError.unsafeConfiguration(url)
            }
        }
        let data = exists ? try Data(contentsOf: url) : nil
        let root: [String: Any]
        if let data, !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else {
                throw AgentHookConfigurationError.invalidConfiguration(url)
            }
            if let hooks = dictionary["hooks"], !(hooks is [String: Any]) {
                throw AgentHookConfigurationError.invalidConfiguration(url)
            }
            if let hooks = dictionary["hooks"] as? [String: Any],
               hooks.values.contains(where: { !($0 is [Any]) }) {
                throw AgentHookConfigurationError.invalidConfiguration(url)
            }
            root = dictionary
        } else {
            root = [:]
        }
        let attributes = exists ? try? fileManager.attributesOfItem(atPath: url.path) : nil
        return Document(
            url: url,
            originalData: data,
            originalMode: attributes?[.posixPermissions] as? NSNumber,
            root: root
        )
    }

    private func write(_ document: Document, fileManager: FileManager) throws {
        let parent = document.url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var data = try JSONSerialization.data(
            withJSONObject: document.root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: document.url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: document.originalMode ?? NSNumber(value: 0o600)],
            ofItemAtPath: document.url.path
        )
    }

    private func restore(_ document: Document, fileManager: FileManager) throws {
        if let originalData = document.originalData {
            try originalData.write(to: document.url, options: .atomic)
            if let mode = document.originalMode {
                try fileManager.setAttributes(
                    [.posixPermissions: mode],
                    ofItemAtPath: document.url.path
                )
            }
        } else if fileManager.fileExists(atPath: document.url.path) {
            try fileManager.removeItem(at: document.url)
        }
    }
}
