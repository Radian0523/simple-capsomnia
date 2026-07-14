import Foundation

struct ProcessExecutionResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

final class ProcessRunner: @unchecked Sendable {
    func run(executablePath: String, arguments: [String]) async -> ProcessExecutionResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let output = Self.read(outputPipe.fileHandleForReading)
                let error = Self.read(errorPipe.fileHandleForReading)
                continuation.resume(returning: ProcessExecutionResult(
                    status: process.terminationStatus,
                    standardOutput: output,
                    standardError: error
                ))
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: ProcessExecutionResult(
                    status: -1,
                    standardOutput: "",
                    standardError: String(describing: error)
                ))
            }
        }
    }

    func runSynchronously(executablePath: String, arguments: [String]) -> ProcessExecutionResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            return ProcessExecutionResult(
                status: process.terminationStatus,
                standardOutput: Self.read(outputPipe.fileHandleForReading),
                standardError: Self.read(errorPipe.fileHandleForReading)
            )
        } catch {
            return ProcessExecutionResult(
                status: -1,
                standardOutput: "",
                standardError: String(describing: error)
            )
        }
    }

    private static func read(_ handle: FileHandle) -> String {
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
