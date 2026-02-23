import AppKit

/// Displays a native macOS-style on-screen display for brightness/volume changes.
/// Uses a borderless, translucent window with a vibrancy effect and a segmented level bar.
final class OSDOverlay {

    enum OSDType {
        case brightness
        case volume
        case mute

        var iconName: String {
            switch self {
            case .brightness: return "sun.max.fill"
            case .volume:     return "speaker.wave.2.fill"
            case .mute:       return "speaker.slash.fill"
            }
        }
    }

    private var window: NSWindow?
    private var hideTimer: Timer?

    private let osdWidth: CGFloat = 220
    private let osdHeight: CGFloat = 24
    private let segmentCount = 16

    static let shared = OSDOverlay()

    private init() {}

    // MARK: - Show OSD

    func show(type: OSDType, level: UInt16, maxLevel: UInt16 = 100) {
        DispatchQueue.main.async { [self] in
            hideTimer?.invalidate()

            let fraction = maxLevel > 0 ? CGFloat(level) / CGFloat(maxLevel) : 0

            if window == nil {
                createWindow()
            }

            guard let window = window,
                  let contentView = window.contentView else { return }

            // Rebuild content
            contentView.subviews.forEach { $0.removeFromSuperview() }
            layoutOSD(in: contentView, type: type, fraction: fraction)

            positionWindow(window)
            window.orderFrontRegardless()
            window.alphaValue = 1.0

            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    // MARK: - Window Creation

    private func createWindow() {
        let frame = NSRect(x: 0, y: 0, width: osdWidth + 60, height: osdHeight + 32)

        let w = NSWindow(contentRect: frame,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        w.contentView = visualEffect

        window = w
    }

    // MARK: - Layout

    private func layoutOSD(in container: NSView, type: OSDType, fraction: CGFloat) {
        let iconSize: CGFloat = 20
        let padding: CGFloat = 16
        let barHeight: CGFloat = 6
        let segmentGap: CGFloat = 2
        let containerBounds = container.bounds

        // Icon
        let icon = NSImageView(frame: NSRect(
            x: padding,
            y: (containerBounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        if let sfImage = NSImage(systemSymbolName: type.iconName,
                                  accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            icon.image = sfImage.withSymbolConfiguration(config)
        }
        icon.contentTintColor = .white
        container.addSubview(icon)

        // Segmented bar
        let barX = padding + iconSize + 10
        let barWidth = containerBounds.width - barX - padding
        let segmentWidth = (barWidth - CGFloat(segmentCount - 1) * segmentGap) / CGFloat(segmentCount)
        let filledSegments = Int(round(fraction * CGFloat(segmentCount)))

        let barY = (containerBounds.height - barHeight) / 2

        for i in 0..<segmentCount {
            let x = barX + CGFloat(i) * (segmentWidth + segmentGap)
            let segmentView = NSView(frame: NSRect(x: x, y: barY,
                                                    width: segmentWidth, height: barHeight))
            segmentView.wantsLayer = true
            segmentView.layer?.cornerRadius = barHeight / 2

            if i < filledSegments {
                segmentView.layer?.backgroundColor = NSColor.white.cgColor
            } else {
                segmentView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            }

            container.addSubview(segmentView)
        }
    }

    // MARK: - Positioning

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        let x = screenFrame.midX - windowFrame.width / 2
        let y = screenFrame.minY + 80

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Fade Out

    private func fadeOut() {
        guard let window = window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
    }
}
