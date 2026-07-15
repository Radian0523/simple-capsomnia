import Darwin
import Foundation

public enum AgentProcessProbe {
    private static let launcherNames: Set<String> = [
        "bash", "dash", "env", "fish", "sh", "timeout", "zsh"
    ]

    public static func hookOwnerIdentity() -> AgentProcessIdentity? {
        var processIdentifier = getppid()

        for _ in 0..<12 where processIdentifier > 1 {
            guard let snapshot = snapshot(processIdentifier: processIdentifier) else {
                return nil
            }
            if !isLauncher(snapshot) {
                return snapshot.identity
            }
            guard snapshot.parentIdentifier > 1,
                  snapshot.parentIdentifier != processIdentifier else {
                return nil
            }
            processIdentifier = snapshot.parentIdentifier
        }
        return nil
    }

    public static func identity(processIdentifier: Int32) -> AgentProcessIdentity? {
        snapshot(processIdentifier: processIdentifier)?.identity
    }

    public static func isRunning(_ identity: AgentProcessIdentity) -> Bool {
        self.identity(processIdentifier: identity.processIdentifier) == identity
    }

    private static func snapshot(processIdentifier: Int32) -> ProcessSnapshot? {
        guard processIdentifier > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(
                processIdentifier,
                PROC_PIDTBSDINFO,
                0,
                pointer,
                expectedSize
            )
        }
        guard result == expectedSize else { return nil }

        let nameCapacity = MemoryLayout.size(ofValue: info.pbi_name)
        let name = withUnsafePointer(to: &info.pbi_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: nameCapacity) {
                String(cString: $0)
            }
        }
        let startTime = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        return ProcessSnapshot(
            identity: AgentProcessIdentity(
                processIdentifier: processIdentifier,
                startTimeMicroseconds: startTime
            ),
            parentIdentifier: Int32(info.pbi_ppid),
            name: name,
            executablePath: executablePath(processIdentifier: processIdentifier)
        )
    }

    private static func executablePath(processIdentifier: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(processIdentifier, pointer.baseAddress, UInt32(pointer.count))
        }
        guard result > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return String(cString: baseAddress)
        }
    }

    private static func isLauncher(_ snapshot: ProcessSnapshot) -> Bool {
        let executableName = snapshot.executablePath.map {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
        }
        return launcherNames.contains(snapshot.name.lowercased())
            || executableName.map(launcherNames.contains) == true
    }

    private struct ProcessSnapshot {
        let identity: AgentProcessIdentity
        let parentIdentifier: Int32
        let name: String
        let executablePath: String?
    }
}
