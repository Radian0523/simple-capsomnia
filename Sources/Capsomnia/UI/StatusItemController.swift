import AppKit
import CapsomniaCore

@MainActor
final class StatusItemController: NSObject {
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var state: SleepControllerState = .stopped
    private var prefersVisible = true

    func update(state: SleepControllerState) {
        self.state = state
        syncVisibility()
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
        if prefersVisible || mustShowError {
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

        switch state {
        case .verified(desired: .preventSleep, _):
            button.image = Self.dot(color: .systemGreen)
            button.toolTip = strings.statusOn
        case .verified(desired: .normalSleep, _):
            button.image = Self.dot(color: .secondaryLabelColor)
            button.toolTip = strings.statusOff
        case .synchronizing:
            button.image = Self.dot(color: .systemRed)
            button.toolTip = strings.statusSynchronizing
        case .degraded, .stopped:
            button.image = Self.dot(color: .systemRed)
            button.toolTip = strings.statusError
        }
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let strings = AppStrings.current()
        let menu = NSMenu()

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

