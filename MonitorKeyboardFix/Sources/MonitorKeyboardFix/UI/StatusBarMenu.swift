import AppKit
import SwiftUI

/// Manages the NSStatusItem in the macOS menu bar and its popover.
final class StatusBarMenu: NSObject {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    let monitorManager: MonitorManager
    var isEnabled: Bool = true {
        didSet {
            updateIcon()
            onEnabledChanged?(isEnabled)
        }
    }
    var onQuit: (() -> Void)?
    var onEnabledChanged: ((Bool) -> Void)?

    init(monitorManager: MonitorManager) {
        self.monitorManager = monitorManager
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        if let button = statusItem?.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        setupPopover()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = isEnabled ? "display" : "display.trianglebadge.exclamationmark"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Monitor Keyboard Fix")
        button.image?.isTemplate = true
    }

    // MARK: - Popover

    private func setupPopover() {
        let isEnabledBinding = Binding<Bool>(
            get: { [weak self] in self?.isEnabled ?? true },
            set: { [weak self] in self?.isEnabled = $0 }
        )

        let popoverView = StatusBarPopoverView(
            monitorManager: monitorManager,
            isEnabled: isEnabledBinding,
            onQuit: { [weak self] in self?.onQuit?() }
        )

        let hostingController = NSHostingController(rootView: popoverView)

        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true

        self.popover = popover
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in
                self?.popover?.performClose(nil)
                if let monitor = self?.eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.eventMonitor = nil
                }
            }
        }
    }
}
