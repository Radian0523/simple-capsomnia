import Foundation

public enum AgentActivityStoreError: Error {
    case unsafeDirectory
    case unsafeStateFile
}

public struct AgentActivityStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL = Self.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    public static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("Capsomnia", isDirectory: true)
            .appendingPathComponent("AgentActivity", isDirectory: true)
    }

    public func write(_ record: AgentActivityRecord, fileManager: FileManager = .default) throws {
        try prepareDirectory(fileManager: fileManager)
        let destination = fileURL(for: record)
        try rejectSymbolicLink(at: destination, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    public func remove(_ record: AgentActivityRecord, fileManager: FileManager = .default) throws {
        let destination = fileURL(for: record)
        try rejectSymbolicLink(at: destination, fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }

    public func loadVisible(
        at date: Date = Date(),
        fileManager: FileManager = .default,
        processIsRunning: (AgentProcessIdentity) -> Bool = AgentProcessProbe.isRunning
    ) throws -> [AgentActivityRecord] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        try validateDirectory(fileManager: fileManager)
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        var records: [AgentActivityRecord] = []

        for file in files where file.pathExtension == "json" {
            let values = try file.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= 65_536 else { continue }
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(AgentActivityRecord.self, from: data) else {
                continue
            }
            let processEnded = record.processIdentity.map { !processIsRunning($0) } ?? false
            if record.isVisible(at: date), !processEnded {
                records.append(record)
            } else {
                try? fileManager.removeItem(at: file)
            }
        }
        return records.sortedForDisplay()
    }

    private func fileURL(for record: AgentActivityRecord) -> URL {
        directoryURL.appendingPathComponent(record.id + ".json", isDirectory: false)
    }

    private func prepareDirectory(fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try validateDirectory(fileManager: fileManager)
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    private func validateDirectory(fileManager: FileManager) throws {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AgentActivityStoreError.unsafeDirectory
        }
    }

    private func rejectSymbolicLink(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw AgentActivityStoreError.unsafeStateFile
        }
    }
}
