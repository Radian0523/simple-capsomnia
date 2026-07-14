import AppKit
import CapsomniaCore
import Darwin
import Foundation

@MainActor
final class ApplicationController: NSObject, NSApplicationDelegate {
    private let configuration = AppConfiguration.load()
    private let runner = ProcessRunner()
    private let logger = AppLogger()
    private let statusController = StatusItemController()
    private var settingsController: SettingsWindowController?
    private var monitor: CapsLockMonitor?
    private var signalSources: [DispatchSourceSignal] = []
    private let signalQueue = DispatchQueue(
        label: "com.github.oonishidaichi.capsomnia.signal-termination"
    )
    private var lastState: SleepControllerState = .stopped
    private var didStartController = false
    private var terminationInProgress = false
    private var skipRestoreOnTerminate = false

    private lazy var stateReader = PmsetStateReader(runner: runner)
    private lazy var helper = HelperClient(configuration: configuration, runner: runner)
    private lazy var launchAgentManager = LaunchAgentManager(
        identity: configuration.identity,
        runner: runner
    )
    private lazy var sleepController = SleepController(
        stateReader: stateReader,
        helper: helper,
        stateHandler: { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleState(state)
            }
        }
    )

    private var openSettingsNotification: Notification.Name {
        Notification.Name("\(configuration.identity.bundleIdentifier).openSettings")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicate() {
            return
        }

        AppPreferences.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        installSignalHandlers()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: openSettingsNotification,
            object: configuration.identity.bundleIdentifier
        )

        if let error = configuration.errorDescription {
            logger.log("event=start configuration=invalid reason=\(error)")
        } else {
            logger.log("event=start configuration=valid flavor=\(configuration.identity.buildFlavor.rawValue)")
        }

        let monitor = CapsLockMonitor { [weak self] capsLockOn, lidClosed in
            self?.handleMonitorTick(capsLockOn: capsLockOn, lidClosed: lidClosed)
        }
        self.monitor = monitor
        monitor.start()

        if !AppPreferences.didCompleteInitialSetup {
            showSettings()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if skipRestoreOnTerminate {
            return .terminateNow
        }
        if terminationInProgress {
            return .terminateLater
        }

        terminationInProgress = true
        monitor?.stop()
        Task { [self] in
            let result = await sleepController.stop()
            logger.logAndWait(
                "event=terminate_restore mode=off status=\(result.status) "
                    + "error=\(AppLogger.sanitize(result.standardError))"
            )
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        for source in signalSources {
            source.cancel()
        }
    }

    private func configureStatusItem() {
        statusController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusController.onRetry = { [weak self] in
            self?.retryNow()
        }
        statusController.onQuit = {
            NSApp.terminate(nil)
        }
        statusController.setPrefersVisible(AppPreferences.showMenuBarIcon)
        statusController.update(state: lastState)
    }

    private func handleMonitorTick(capsLockOn: Bool, lidClosed: Bool?) {
        if !didStartController {
            didStartController = true
            Task { [self] in
                await sleepController.start(
                    capsLockOn: capsLockOn,
                    lidClosed: lidClosed,
                    displaySleepOnLidClose: AppPreferences.displaySleepOnLidClose
                )
            }
        } else {
            Task { [self] in
                await sleepController.update(
                    capsLockOn: capsLockOn,
                    lidClosed: lidClosed,
                    displaySleepOnLidClose: AppPreferences.displaySleepOnLidClose
                )
            }
        }
    }

    private func handleState(_ state: SleepControllerState) {
        lastState = state
        statusController.update(state: state)
        settingsController?.update(state: state)
        logger.log("event=state value=\(logDescription(for: state))")
    }

    private func showSettings() {
        if settingsController == nil {
            settingsController = makeSettingsController()
        }
        settingsController?.show(state: lastState)
    }

    private func makeSettingsController() -> SettingsWindowController {
        SettingsWindowController(
            onShowMenuBarChange: { [weak self] enabled in
                AppPreferences.showMenuBarIcon = enabled
                self?.statusController.setPrefersVisible(enabled)
                self?.logger.log("event=preference key=menu_bar value=\(enabled)")
            },
            onLaunchAtLoginChange: { [weak self] enabled in
                guard let self else { return }
                let previous = AppPreferences.launchAtLogin
                AppPreferences.launchAtLogin = enabled
                Task { [self] in
                    let succeeded = await self.launchAgentManager.setEnabled(enabled)
                    if !succeeded {
                        AppPreferences.launchAtLogin = previous
                        self.settingsController?.reloadText()
                    }
                    self.logger.log(
                        "event=preference key=launch_at_login value=\(enabled) status=\(succeeded ? "ok" : "failed")"
                    )
                }
            },
            onDisplaySleepChange: { [weak self] enabled in
                AppPreferences.displaySleepOnLidClose = enabled
                self?.logger.log("event=preference key=display_sleep value=\(enabled)")
            },
            onLanguageChange: { [weak self] language in
                AppPreferences.language = language
                self?.statusController.reloadText()
                self?.settingsController?.reloadText()
                self?.logger.log("event=preference key=language value=\(language.rawValue)")
            },
            onRetry: { [weak self] in
                self?.retryNow()
            },
            onDone: { [weak self] in
                AppPreferences.didCompleteInitialSetup = true
                self?.logger.log("event=initial_setup status=complete")
            }
        )
    }

    private func retryNow() {
        logger.log("event=manual_retry")
        Task { [self] in
            await sleepController.retryNow()
        }
    }

    private func terminateIfDuplicate() -> Bool {
        guard Bundle.main.bundleIdentifier == configuration.identity.bundleIdentifier else {
            return false
        }

        let currentPID = getpid()
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: configuration.identity.bundleIdentifier)
            .first { !$0.isTerminated && $0.processIdentifier != currentPID }
        guard let existing else { return false }

        skipRestoreOnTerminate = true
        DistributedNotificationCenter.default().post(
            name: openSettingsNotification,
            object: configuration.identity.bundleIdentifier
        )
        existing.activate(options: [])
        NSApp.terminate(nil)
        return true
    }

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        showSettings()
    }

    private func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let restorer = SignalTerminationRestorer(helper: helper, logger: logger)

        for signalNumber in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
            source.setEventHandler {
                restorer.restoreAndExit(signalNumber: signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func logDescription(for state: SleepControllerState) -> String {
        switch state {
        case .stopped:
            "stopped"
        case let .synchronizing(desired, generation):
            "synchronizing desired=\(desired.rawValue) generation=\(generation)"
        case let .verified(desired, _):
            "verified desired=\(desired.rawValue)"
        case let .degraded(desired, failure, _):
            "degraded desired=\(desired.rawValue) failure=\(failureDescription(failure))"
        }
    }

    private func failureDescription(_ failure: ControllerFailure) -> String {
        switch failure {
        case let .helper(status, message):
            "helper status=\(status) reason=\(AppLogger.sanitize(message))"
        case .stateUnavailable:
            "state_unavailable"
        case .stateMismatch:
            "state_mismatch"
        }
    }
}
