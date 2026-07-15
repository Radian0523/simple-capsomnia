import AppKit
import CapsomniaAgentCore
import CapsomniaCore

@MainActor
final class StatusItemController: NSObject {
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var state: SleepControllerState = .stopped
    private var agentActivities: [AgentActivityRecord] = []
    private var prefersVisible = true

    func update(state: SleepControllerState) {
        self.state = state
        syncVisibility()
        rebuildMenu()
        render()
    }

    func update(agentActivities: [AgentActivityRecord]) {
        self.agentActivities = agentActivities.sortedForDisplay()
        syncVisibility()
        rebuildMenu()
        render()
    }

    func setPrefersVisible(_ visible: Bool) {
        prefersVisible = visible
        syncVisibility()
        render()
    }

    func reloadText() {
        rebuildMenu()
        render()
    }

    private var mustShowError: Bool {
        switch state {
        case .verified:
            false
        case .stopped, .synchronizing, .degraded:
            true
        }
    }

    private func syncVisibility() {
        if prefersVisible || mustShowError || !agentActivities.isEmpty {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: 24)
                item.button?.imagePosition = .imageOnly
                statusItem = item
                rebuildMenu()
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        let strings = AppStrings.current()
        let agentColor = agentIndicatorColor

        switch state {
        case .verified(desired: .preventSleep, _):
            button.image = Self.statusImage(sleepColor: .systemGreen, agentColor: agentColor)
            button.toolTip = combinedToolTip(sleepStatus: strings.statusOn)
        case .verified(desired: .normalSleep, _):
            button.image = Self.statusImage(
                sleepColor: .secondaryLabelColor,
                agentColor: agentColor
            )
            button.toolTip = combinedToolTip(sleepStatus: strings.statusOff)
        case .synchronizing:
            button.image = Self.statusImage(sleepColor: .systemRed, agentColor: agentColor)
            button.toolTip = combinedToolTip(sleepStatus: strings.statusSynchronizing)
        case .degraded, .stopped:
            button.image = Self.statusImage(sleepColor: .systemRed, agentColor: agentColor)
            button.toolTip = combinedToolTip(sleepStatus: strings.statusError)
        }
        statusItem?.length = agentActivities.isEmpty ? 24 : 40
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let strings = AppStrings.current()
        let menu = NSMenu()

        if !agentActivities.isEmpty {
            let heading = NSMenuItem(title: strings.agentActivityHeading, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for record in agentActivities.prefix(8) {
                let title = "\(record.provider.displayName)  \(strings.agentPhase(record.phase)) — \(record.projectName)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.image = NSImage(
                    systemSymbolName: "terminal.fill",
                    accessibilityDescription: record.provider.displayName
                )
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let open = NSMenuItem(
            title: strings.openSettings,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        open.target = self
        menu.addItem(open)

        let retry = NSMenuItem(
            title: strings.retry,
            action: #selector(retry),
            keyEquivalent: "r"
        )
        retry.target = self
        menu.addItem(retry)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: strings.quit,
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func retry() {
        onRetry?()
    }

    @objc private func quit() {
        onQuit?()
    }

    private var agentIndicatorColor: NSColor? {
        if agentActivities.contains(where: { $0.phase == .attention }) { return .systemOrange }
        if agentActivities.contains(where: { $0.phase == .failed }) { return .systemRed }
        if agentActivities.contains(where: { $0.phase == .working }) { return .systemBlue }
        if !agentActivities.isEmpty { return .secondaryLabelColor }
        return nil
    }

    private func combinedToolTip(sleepStatus: String) -> String {
        guard let first = agentActivities.first else { return sleepStatus }
        let strings = AppStrings.current()
        let agentStatus = "\(first.provider.displayName): \(strings.agentPhase(first.phase))"
        if agentActivities.count == 1 { return sleepStatus + "\n" + agentStatus }
        return sleepStatus + "\n" + agentStatus + " (+\(agentActivities.count - 1))"
    }

    private static func statusImage(sleepColor: NSColor, agentColor: NSColor?) -> NSImage {
        let size = NSSize(width: agentColor == nil ? 12 : 30, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            sleepColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 2, width: 10, height: 10)).fill()
            guard let agentColor else { return true }

            let symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 11,
                weight: .medium
            ).applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
            let symbol = NSImage(
                systemSymbolName: "terminal.fill",
                accessibilityDescription: "Agent Activity"
            )?.withSymbolConfiguration(symbolConfiguration)
            symbol?.draw(
                in: NSRect(x: 14, y: 1, width: 13, height: 12),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            agentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 25, y: 1, width: 5, height: 5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
