import Foundation

final class AppLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.github.oonishidaichi.capsomnia.logger")
    private let logURL: URL
    private let rotatedURL: URL
    private let maxBytes: UInt64 = 1_048_576

    init(fileManager: FileManager = .default) {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Capsomnia", isDirectory: true)
        logURL = directory.appendingPathComponent("capsomnia.log")
        rotatedURL = directory.appendingPathComponent("capsomnia.log.1")
    }

    func log(_ event: String) {
        let cleanEvent = Self.sanitize(event)
        queue.async { [self] in
            write(cleanEvent)
        }
    }

    func logAndWait(_ event: String) {
        let cleanEvent = Self.sanitize(event)
        queue.sync { [self] in
            write(cleanEvent)
        }
    }

    static func sanitize(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars.prefix(2_048) {
            if !CharacterSet.controlCharacters.contains(scalar) || scalar == "\t" {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private func write(_ cleanEvent: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
               let size = attributes[.size] as? NSNumber,
               size.uint64Value >= maxBytes {
                try? fileManager.removeItem(at: rotatedURL)
                try fileManager.moveItem(at: logURL, to: rotatedURL)
            }

            let line = "\(ISO8601DateFormatter().string(from: Date())) \(cleanEvent)\n"
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging must never change power-management behavior.
        }
    }
}
