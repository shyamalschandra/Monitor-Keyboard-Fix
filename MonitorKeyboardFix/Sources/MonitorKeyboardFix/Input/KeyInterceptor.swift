import Foundation
import CoreGraphics
import AppKit

/// Intercepts system-defined media key events (brightness, volume) via a CGEvent tap.
/// Requires Accessibility permission in System Settings > Privacy & Security > Accessibility.
final class KeyInterceptor {

    // NX key types from IOKit/hidsystem/ev_keymap.h
    private static let NX_KEYTYPE_SOUND_UP: UInt32     = 0
    private static let NX_KEYTYPE_SOUND_DOWN: UInt32   = 1
    private static let NX_KEYTYPE_MUTE: UInt32         = 7
    private static let NX_KEYTYPE_BRIGHTNESS_UP: UInt32   = 2
    private static let NX_KEYTYPE_BRIGHTNESS_DOWN: UInt32 = 3

    weak var delegate: MediaKeyDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Whether the interceptor is actively capturing key events.
    private(set) var isRunning = false

    /// Whether to consume (swallow) the intercepted key events so they don't
    /// reach the system's default handler. Set to true when external monitors
    /// are detected.
    var shouldConsumeEvents = true

    // MARK: - Accessibility Check

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        guard KeyInterceptor.checkAccessibilityPermission() else {
            NSLog("[KeyInterceptor] Accessibility permission not granted. "
                + "Please enable in System Settings > Privacy & Security > Accessibility.")
            return
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
            | 1 << CGEventType.keyUp.rawValue
            | (1 << 14)  // NSEventType.systemDefined = 14

        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: KeyInterceptor.eventCallback,
            userInfo: unsafeSelf
        ) else {
            NSLog("[KeyInterceptor] Failed to create event tap. Accessibility permission may be required.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        NSLog("[KeyInterceptor] Event tap started.")
    }

    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false
        NSLog("[KeyInterceptor] Event tap stopped.")
    }

    // MARK: - Event Callback

    private static let eventCallback: CGEventTapCallBack = {
        (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in

        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let nsEvent = NSEvent(cgEvent: event)
        guard nsEvent?.type == .systemDefined, nsEvent?.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = nsEvent else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = UInt32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8  // 0xA = key down, 0xB = key up
        let isKeyDown = keyState == 0x0A

        guard isKeyDown else {
            return Unmanaged.passUnretained(event)
        }

        let action: MediaKeyAction?
        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_UP:
            action = .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            action = .brightnessDown
        case NX_KEYTYPE_SOUND_UP:
            action = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN:
            action = .volumeDown
        case NX_KEYTYPE_MUTE:
            action = .mute
        default:
            action = nil
        }

        if let action = action {
            DispatchQueue.main.async {
                interceptor.delegate?.handleMediaKey(action)
            }
            if interceptor.shouldConsumeEvents {
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
