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
    private var hoverView: StatusItemHoverView?
    private var hoverPopover: NSPopover?
    private var hoverLabel: NSTextField?
    private var hoverText = ""

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
                if let button = item.button {
                    installHoverTracking(on: button)
                }
                rebuildMenu()
            }
        } else if let statusItem {
            hoverPopover?.close()
            hoverView?.removeFromSuperview()
            hoverView = nil
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        let strings = AppStrings.current()

        switch state {
        case .verified(desired: .preventSleep, _):
            button.image = Self.dot(color: combinedIndicatorColor(sleepColor: .systemGreen))
            button.toolTip = combinedToolTip(sleepStatus: strings.statusOn)
        case .verified(desired: .normalSleep, _):
            button.image = Self.dot(color: combinedIndicatorColor(sleepColor: .secondaryLabelColor))
            button.toolTip = combinedToolTip(sleepStatus: strings.statusOff)
        case .synchronizing:
            button.image = Self.dot(color: .systemRed)
            button.toolTip = combinedToolTip(sleepStatus: strings.statusSynchronizing)
        case .degraded, .stopped:
            button.image = Self.dot(color: .systemRed)
            button.toolTip = combinedToolTip(sleepStatus: strings.statusError)
        }
        hoverText = button.toolTip ?? ""
        if hoverPopover?.isShown == true {
            updateHoverContent()
        }
        statusItem?.length = 24
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

    private func combinedIndicatorColor(sleepColor: NSColor) -> NSColor {
        if agentActivities.contains(where: { $0.phase == .attention }) { return .systemOrange }
        if agentActivities.contains(where: { $0.phase == .failed }) { return .systemRed }
        if agentActivities.contains(where: { $0.phase == .working }) { return .systemBlue }
        return sleepColor
    }

    private func combinedToolTip(sleepStatus: String) -> String {
        let strings = AppStrings.current()
        var lines = [sleepStatus]

        guard AppPreferences.agentActivityEnabled else {
            lines.append(strings.agentActivityDisabled)
            return lines.joined(separator: "\n")
        }
        guard !agentActivities.isEmpty else {
            lines.append(strings.agentActivityNone)
            return lines.joined(separator: "\n")
        }

        lines.append(contentsOf: agentActivities.prefix(4).map { record in
            "\(record.provider.displayName): \(strings.agentPhase(record.phase)) — \(record.projectName)"
        })
        if agentActivities.count > 4 {
            lines.append("+\(agentActivities.count - 4)")
        }
        return lines.joined(separator: "\n")
    }

    private func installHoverTracking(on button: NSStatusBarButton) {
        let hoverView = StatusItemHoverView()
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.onEnter = { [weak self] in
            self?.showHoverPopover()
        }
        hoverView.onExit = { [weak self] in
            self?.hoverPopover?.close()
        }
        button.addSubview(hoverView)
        NSLayoutConstraint.activate([
            hoverView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hoverView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hoverView.topAnchor.constraint(equalTo: button.topAnchor),
            hoverView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        self.hoverView = hoverView
    }

    private func showHoverPopover() {
        guard let button = statusItem?.button, !hoverText.isEmpty else { return }
        updateHoverContent()
        hoverPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateHoverContent() {
        let popover = preparedHoverPopover()
        hoverLabel?.stringValue = hoverText

        let maximumTextWidth: CGFloat = 320
        let font = hoverLabel?.font ?? .systemFont(ofSize: 13)
        let textBounds = (hoverText as NSString).boundingRect(
            with: NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let width = min(max(ceil(textBounds.width) + 24, 180), maximumTextWidth + 24)
        let height = min(max(ceil(textBounds.height) + 24, 42), 240)
        hoverLabel?.preferredMaxLayoutWidth = width - 24
        popover.contentSize = NSSize(width: width, height: height)
    }

    private func preparedHoverPopover() -> NSPopover {
        if let hoverPopover { return hoverPopover }

        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        let viewController = NSViewController()
        viewController.view = contentView

        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .applicationDefined
        popover.contentViewController = viewController
        hoverLabel = label
        hoverPopover = popover
        return popover
    }

    private static func dot(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

@MainActor
private final class StatusItemHoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
