import Foundation
import CoreGraphics
import AppKit

/// Intercepts system-defined media key events (brightness, volume) via a CGEvent tap.
/// Requires Accessibility permission in System Settings > Privacy & Security > Accessibility.
final class KeyInterceptor {

    // NX key types from IOKit/hidsystem/ev_keymap.h
    private static let NX_KEYTYPE_SOUND_UP: UInt32        = 0
    private static let NX_KEYTYPE_SOUND_DOWN: UInt32      = 1
    private static let NX_KEYTYPE_BRIGHTNESS_UP: UInt32   = 2
    private static let NX_KEYTYPE_BRIGHTNESS_DOWN: UInt32 = 3
    private static let NX_KEYTYPE_MUTE: UInt32            = 7
    // Alternative key types used on some Mac models / keyboard configs
    private static let NX_KEYTYPE_ILLUMINATION_UP: UInt32   = 21
    private static let NX_KEYTYPE_ILLUMINATION_DOWN: UInt32 = 22

    weak var delegate: MediaKeyDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private(set) var isRunning = false

    /// Whether to consume (swallow) the intercepted key events so they don't
    /// reach the system's default handler.
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

        // We need NX_SYSDEFINED (subtype 8) events which come through as
        // CGEventType rawValue 14. Also listen for regular key events as a
        // fallback for some keyboard configurations.
        let eventMask: CGEventMask = (1 << 14)  // NSEvent.EventType.systemDefined
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

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
        NSLog("[KeyInterceptor] Event tap started successfully.")
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

        // Re-enable the tap if macOS disabled it due to timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[KeyInterceptor] Event tap was disabled (type=%d), re-enabling.", type.rawValue)
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // We only care about NX_SYSDEFINED events (subtype 8 = media/special keys)
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        guard nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = UInt32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A
        let isRepeat = (keyFlags & 0x01) != 0

        NSLog("[KeyInterceptor] SystemDefined event: keyCode=%d keyState=0x%02X isRepeat=%d data1=0x%08X",
              keyCode, keyState, isRepeat ? 1 : 0, data1)

        // Process both key-down and key-repeat events
        guard isKeyDown else {
            return Unmanaged.passUnretained(event)
        }

        let action: MediaKeyAction?
        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_ILLUMINATION_UP:
            action = .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN, NX_KEYTYPE_ILLUMINATION_DOWN:
            action = .brightnessDown
        case NX_KEYTYPE_SOUND_UP:
            action = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN:
            action = .volumeDown
        case NX_KEYTYPE_MUTE:
            action = .mute
        default:
            NSLog("[KeyInterceptor] Unhandled key code: %d", keyCode)
            action = nil
        }

        if let action = action {
            NSLog("[KeyInterceptor] Dispatching action: %@",
                  String(describing: action))
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
