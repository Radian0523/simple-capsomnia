import CapsomniaPmsetHelperCore
import Darwin
import Foundation

final class SignalTerminationRestorer: @unchecked Sendable {
    private let helper: HelperClient
    private let logger: AppLogger
    private var restorationStarted = false

    init(helper: HelperClient, logger: AppLogger) {
        self.helper = helper
        self.logger = logger
    }

    func restoreAndExit(signalNumber: Int32) {
        guard !restorationStarted else { return }
        restorationStarted = true

        logger.log("event=signal value=\(signalNumber)")
        let result = helper.runSynchronously(.off)
        logger.logAndWait(
            "event=terminate_restore mode=off status=\(result.status) "
                + "error=\(AppLogger.sanitize(result.standardError))"
        )
        Darwin.exit(result.status == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
