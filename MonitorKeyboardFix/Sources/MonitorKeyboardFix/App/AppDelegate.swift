import AppKit

/// Main application delegate that wires together monitor discovery, keyboard
/// interception, DDC control, and the menu bar UI.
final class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyDelegate {

    let monitorManager = MonitorManager()
    let keyInterceptor = KeyInterceptor()
    var statusBarMenu: StatusBarMenu!

    private let osd = OSDOverlay.shared

    private let brightnessStep: Int16 = 6
    private let volumeStep: Int16 = 6

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[MonitorKeyboardFix] Starting up...")

        statusBarMenu = StatusBarMenu(monitorManager: monitorManager)
        statusBarMenu.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        statusBarMenu.onEnabledChanged = { [weak self] enabled in
            guard let self = self else { return }
            if enabled {
                self.keyInterceptor.start()
            } else {
                self.keyInterceptor.stop()
            }
        }
        statusBarMenu.setup()

        monitorManager.discoverMonitors()

        keyInterceptor.delegate = self
        keyInterceptor.shouldConsumeEvents = true
        keyInterceptor.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSLog("[MonitorKeyboardFix] Ready. Found %d monitor(s). Key interceptor running: %d",
              monitorManager.monitors.count, keyInterceptor.isRunning ? 1 : 0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyInterceptor.stop()
        NSLog("[MonitorKeyboardFix] Shutting down.")
    }

    // MARK: - Display Change

    @objc private func displaysChanged() {
        NSLog("[MonitorKeyboardFix] Display configuration changed. Re-scanning...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.monitorManager.discoverMonitors()
        }
    }

    // MARK: - MediaKeyDelegate

    func handleMediaKey(_ action: MediaKeyAction) {
        NSLog("[MonitorKeyboardFix] handleMediaKey: %@ (enabled=%d, monitors=%d)",
              String(describing: action), statusBarMenu.isEnabled ? 1 : 0,
              monitorManager.monitors.count)

        guard statusBarMenu.isEnabled else { return }

        switch action {
        case .brightnessUp:
            monitorManager.adjustBrightnessAll(by: brightnessStep)
            showBrightnessOSD()

        case .brightnessDown:
            monitorManager.adjustBrightnessAll(by: -brightnessStep)
            showBrightnessOSD()

        case .volumeUp:
            monitorManager.adjustVolumeAll(by: volumeStep)
            showVolumeOSD()

        case .volumeDown:
            monitorManager.adjustVolumeAll(by: -volumeStep)
            showVolumeOSD()

        case .mute:
            monitorManager.toggleMuteAll()
            let isMuted = monitorManager.monitors.first?.isMuted ?? false
            osd.show(type: isMuted ? .mute : .volume,
                     level: isMuted ? 0 : monitorManager.averageVolume)
        }
    }

    private func showBrightnessOSD() {
        let level = monitorManager.averageBrightness
        NSLog("[MonitorKeyboardFix] OSD brightness level: %d", level)
        osd.show(type: .brightness, level: level)
    }

    private func showVolumeOSD() {
        let level = monitorManager.averageVolume
        NSLog("[MonitorKeyboardFix] OSD volume level: %d", level)
        osd.show(type: .volume, level: level)
    }
}
