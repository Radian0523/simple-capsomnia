import AppKit
import CapsomniaAgentCore
import CapsomniaCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let onShowMenuBarChange: (Bool) -> Void
    private let onLaunchAtLoginChange: (Bool) -> Void
    private let onDisplaySleepChange: (Bool) -> Void
    private let onAgentActivityChange: (Bool) -> Bool
    private let onLanguageChange: (AppLanguage) -> Void
    private let onRetry: () -> Void
    private let onDone: () -> Void

    private var currentState: SleepControllerState = .stopped
    private var currentAgentActivities: [AgentActivityRecord] = []
    private var currentCodexHookTrustState: CodexHookTrustState = .checking
    private var titleLabel: NSTextField!
    private var statusHeadingLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var settingsHeadingLabel: NSTextField!
    private var warningLabel: NSTextField!
    private var showMenuBarSwitch: NSSwitch!
    private var showMenuBarLabel: NSTextField!
    private var launchAtLoginSwitch: NSSwitch!
    private var launchAtLoginLabel: NSTextField!
    private var displaySleepSwitch: NSSwitch!
    private var displaySleepLabel: NSTextField!
    private var agentActivityHeadingLabel: NSTextField!
    private var agentActivityStatusLabel: NSTextField!
    private var agentActivitySwitch: NSSwitch!
    private var agentActivityLabel: NSTextField!
    private var languageLabel: NSTextField!
    private var languagePopup: NSPopUpButton!
    private var retryButton: NSButton!
    private var doneButton: NSButton!

    init(
        onShowMenuBarChange: @escaping (Bool) -> Void,
        onLaunchAtLoginChange: @escaping (Bool) -> Void,
        onDisplaySleepChange: @escaping (Bool) -> Void,
        onAgentActivityChange: @escaping (Bool) -> Bool,
        onLanguageChange: @escaping (AppLanguage) -> Void,
        onRetry: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.onShowMenuBarChange = onShowMenuBarChange
        self.onLaunchAtLoginChange = onLaunchAtLoginChange
        self.onDisplaySleepChange = onDisplaySleepChange
        self.onAgentActivityChange = onAgentActivityChange
        self.onLanguageChange = onLanguageChange
        self.onRetry = onRetry
        self.onDone = onDone

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        reloadText()
        reloadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        state: SleepControllerState,
        agentActivities: [AgentActivityRecord],
        codexHookTrustState: CodexHookTrustState
    ) {
        currentState = state
        currentAgentActivities = agentActivities
        currentCodexHookTrustState = codexHookTrustState
        reloadStatus()
        reloadAgentStatus()
        reloadValues()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(state: SleepControllerState) {
        currentState = state
        reloadStatus()
    }

    func update(agentActivities: [AgentActivityRecord]) {
        currentAgentActivities = agentActivities
        reloadAgentStatus()
    }

    func update(codexHookTrustState: CodexHookTrustState) {
        currentCodexHookTrustState = codexHookTrustState
        reloadAgentStatus()
    }

    func reloadText() {
        guard isWindowLoaded else { return }
        let strings = AppStrings.current()
        window?.title = strings.title
        titleLabel.stringValue = strings.title
        statusHeadingLabel.stringValue = strings.statusHeading
        settingsHeadingLabel.stringValue = strings.settingsHeading
        warningLabel.stringValue = strings.warning
        showMenuBarLabel.stringValue = strings.showMenuBarIcon
        launchAtLoginLabel.stringValue = strings.launchAtLogin
        displaySleepLabel.stringValue = strings.displaySleepOnLidClose
        agentActivityHeadingLabel.stringValue = strings.agentActivityHeading
        agentActivityLabel.stringValue = strings.agentActivityEnabled
        languageLabel.stringValue = strings.language
        retryButton.title = strings.retry
        doneButton.title = strings.done

        languagePopup.removeAllItems()
        for language in AppLanguage.allCases {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        languagePopup.selectItem(withTitle: AppPreferences.language.displayName)
        reloadStatus()
        reloadAgentStatus()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        statusHeadingLabel = headingLabel()
        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        settingsHeadingLabel = headingLabel()
        warningLabel = NSTextField(wrappingLabelWithString: "")
        warningLabel.textColor = .secondaryLabelColor

        showMenuBarSwitch = makeSwitch(action: #selector(showMenuBarChanged))
        showMenuBarLabel = NSTextField(labelWithString: "")
        launchAtLoginSwitch = makeSwitch(action: #selector(launchAtLoginChanged))
        launchAtLoginLabel = NSTextField(labelWithString: "")
        displaySleepSwitch = makeSwitch(action: #selector(displaySleepChanged))
        displaySleepLabel = NSTextField(labelWithString: "")
        agentActivityHeadingLabel = headingLabel()
        agentActivityStatusLabel = NSTextField(wrappingLabelWithString: "")
        agentActivityStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        agentActivitySwitch = makeSwitch(action: #selector(agentActivityChanged))
        agentActivityLabel = NSTextField(labelWithString: "")
        languageLabel = NSTextField(labelWithString: "")
        languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        retryButton = NSButton(title: "", target: self, action: #selector(retry))
        doneButton = NSButton(title: "", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            titleLabel,
            statusHeadingLabel,
            statusLabel,
            separator(),
            settingsHeadingLabel,
            settingRow(label: showMenuBarLabel, control: showMenuBarSwitch),
            settingRow(label: launchAtLoginLabel, control: launchAtLoginSwitch),
            settingRow(label: displaySleepLabel, control: displaySleepSwitch),
            settingRow(label: languageLabel, control: languagePopup),
            separator(),
            agentActivityHeadingLabel,
            agentActivityStatusLabel,
            settingRow(label: agentActivityLabel, control: agentActivitySwitch),
            warningLabel,
            buttonRow()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            warningLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            agentActivityStatusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func headingLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSwitch(action: Selector) -> NSSwitch {
        let control = NSSwitch()
        control.target = self
        control.action = action
        return control
    }

    private func settingRow(label: NSTextField, control: NSView) -> NSView {
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 464).isActive = true
        return row
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 464).isActive = true
        return view
    }

    private func buttonRow() -> NSView {
        let spacer = NSView()
        let row = NSStackView(views: [retryButton, spacer, doneButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 464).isActive = true
        return row
    }

    private func reloadValues() {
        guard isWindowLoaded else { return }
        showMenuBarSwitch.state = AppPreferences.showMenuBarIcon ? .on : .off
        launchAtLoginSwitch.state = AppPreferences.launchAtLogin ? .on : .off
        displaySleepSwitch.state = AppPreferences.displaySleepOnLidClose ? .on : .off
        agentActivitySwitch.state = AppPreferences.agentActivityEnabled ? .on : .off
        languagePopup.selectItem(withTitle: AppPreferences.language.displayName)
    }

    private func reloadAgentStatus() {
        guard isWindowLoaded else { return }
        let strings = AppStrings.current()
        guard AppPreferences.agentActivityEnabled else {
            agentActivityStatusLabel.stringValue = strings.agentActivityDisabled
            agentActivityStatusLabel.textColor = .secondaryLabelColor
            return
        }
        var lines: [String] = []
        if let codexStatus = strings.codexHookStatus(currentCodexHookTrustState) {
            lines.append(codexStatus)
        }
        lines.append(contentsOf: currentAgentActivities.prefix(4).map { record in
            "\(record.provider.displayName): \(strings.agentPhase(record.phase)) — \(record.projectName)"
        })
        if lines.isEmpty {
            lines.append(strings.agentActivityNone)
        }
        agentActivityStatusLabel.stringValue = lines.joined(separator: "\n")

        if currentCodexHookTrustState == .approvalRequired
            || currentCodexHookTrustState == .modified
            || currentAgentActivities.contains(where: { $0.phase == .attention }) {
            agentActivityStatusLabel.textColor = .systemOrange
        } else if currentAgentActivities.contains(where: { $0.phase == .failed }) {
            agentActivityStatusLabel.textColor = .systemRed
        } else if currentAgentActivities.contains(where: { $0.phase == .working }) {
            agentActivityStatusLabel.textColor = .systemBlue
        } else {
            agentActivityStatusLabel.textColor = .labelColor
        }
    }

    private func reloadStatus() {
        guard isWindowLoaded else { return }
        let strings = AppStrings.current()
        switch currentState {
        case .verified(desired: .preventSleep, _):
            statusLabel.stringValue = strings.statusOn
            statusLabel.textColor = .systemGreen
        case .verified(desired: .normalSleep, _):
            statusLabel.stringValue = strings.statusOff
            statusLabel.textColor = .labelColor
        case .synchronizing:
            statusLabel.stringValue = strings.statusSynchronizing
            statusLabel.textColor = .systemRed
        case .degraded, .stopped:
            statusLabel.stringValue = strings.statusError
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func showMenuBarChanged() {
        onShowMenuBarChange(showMenuBarSwitch.state == .on)
    }

    @objc private func launchAtLoginChanged() {
        onLaunchAtLoginChange(launchAtLoginSwitch.state == .on)
    }

    @objc private func displaySleepChanged() {
        onDisplaySleepChange(displaySleepSwitch.state == .on)
    }

    @objc private func agentActivityChanged() {
        let requested = agentActivitySwitch.state == .on
        if !onAgentActivityChange(requested) {
            agentActivitySwitch.state = AppPreferences.agentActivityEnabled ? .on : .off
        }
        reloadAgentStatus()
    }

    @objc private func languageChanged() {
        guard let raw = languagePopup.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        onLanguageChange(language)
    }

    @objc private func retry() {
        onRetry()
    }

    @objc private func done() {
        onDone()
        close()
    }
}
