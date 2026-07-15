import CapsomniaAgentCore
import Foundation

final class CodexHookTrustInspector: @unchecked Sendable {
    private let fileManager: FileManager
    private let timeout: DispatchTimeInterval

    init(fileManager: FileManager = .default, timeout: DispatchTimeInterval = .seconds(5)) {
        self.fileManager = fileManager
        self.timeout = timeout
    }

    func inspect(workingDirectoryURL: URL) async -> CodexHookTrustState {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                continuation.resume(returning: inspectSynchronously(
                    workingDirectoryURL: workingDirectoryURL
                ))
            }
        }
    }

    private func inspectSynchronously(workingDirectoryURL: URL) -> CodexHookTrustState {
        guard let executableURL = codexExecutableURL() else { return .unavailable }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let response = LockedResponse()
        let responseReady = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = workingDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in response.append(data) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let identifier = object["id"] as? NSNumber else { continue }
                if identifier.intValue == 1 {
                    Self.write([
                        "method": "initialized"
                    ], to: inputPipe.fileHandleForWriting)
                    Self.write([
                        "id": 2,
                        "method": "hooks/list",
                        "params": ["cwds": [workingDirectoryURL.path]]
                    ], to: inputPipe.fileHandleForWriting)
                } else if identifier.intValue == 2 {
                    response.complete(with: line)
                    responseReady.signal()
                }
            }
        }

        do {
            try process.run()
            Self.write([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "capsomnia",
                        "version": Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "development"
                    ],
                    "capabilities": ["experimentalApi": true]
                ]
            ], to: inputPipe.fileHandleForWriting)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            return .unavailable
        }

        let waitResult = responseReady.wait(timeout: .now() + timeout)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }

        guard waitResult == .success, let data = response.completedData else {
            return .unavailable
        }
        return CodexHooksListResponseParser.trustState(from: data) ?? .unavailable
    }

    private func codexExecutableURL() -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? handle.write(contentsOf: data)
    }
}

private final class LockedResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var result: Data?

    var completedData: Data? {
        lock.withLock { result }
    }

    func append(_ data: Data) -> [Data] {
        lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if !line.isEmpty {
                    lines.append(Data(line))
                }
            }
            return lines
        }
    }

    func complete(with data: Data) {
        lock.withLock {
            result = data
        }
    }
}
