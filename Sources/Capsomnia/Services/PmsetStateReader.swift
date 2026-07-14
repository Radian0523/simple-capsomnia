import CapsomniaCore
import Foundation

final class PmsetStateReader: SleepStateReading, @unchecked Sendable {
    private let runner: ProcessRunner

    init(runner: ProcessRunner) {
        self.runner = runner
    }

    func readSleepDisabled() async -> Bool? {
        let result = await runner.run(executablePath: "/usr/bin/pmset", arguments: ["-g"])
        guard result.status == 0 else { return nil }
        return SleepStateParser.parse(result.standardOutput)
    }
}

