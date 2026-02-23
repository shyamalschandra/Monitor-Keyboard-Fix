import Foundation
import IOKit
import IOKit.hid
import AppKit

/// Intercepts brightness and volume HID key events directly from the keyboard
/// hardware via IOHIDManager. This approach works even when macOS consumes the
/// SystemDefined events at the WindowServer level (common on Mac Studio/Mac Mini
/// with only external USB-C displays running macOS Sonoma+).
///
/// Falls back gracefully if the CGEvent tap in KeyInterceptor already handles
/// the keys (e.g., on MacBook with built-in display).
final class HIDKeyInterceptor {

    weak var delegate: MediaKeyDelegate?

    private var hidManager: IOHIDManager?
    private(set) var isRunning = false

    /// Tracks whether CGEvent-based KeyInterceptor has received brightness events.
    /// If it has, HID interceptor defers to it to avoid double-handling.
    var cgEventTapHandlesBrightness = false

    // HID usage IDs for Consumer Page (0x0C)
    private static let usageConsumerPage: UInt32 = 0x0C
    private static let usageBrightnessUp: UInt32 = 0x006F
    private static let usageBrightnessDown: UInt32 = 0x0070
    private static let usageVolumeUp: UInt32 = 0x00E9
    private static let usageVolumeDown: UInt32 = 0x00EA
    private static let usageMute: UInt32 = 0x00E2

    // Keyboard Page (0x07) - F14/F15 used as brightness on some configs
    private static let usageKeyboardPage: UInt32 = 0x07
    private static let usageF14: UInt32 = 0x69
    private static let usageF15: UInt32 = 0x6A

    // Apple vendor-specific top case page
    private static let usageAppleVendorTopCase: UInt32 = 0xFF
    private static let usageBrightnessUpTopCase: UInt32 = 0x04
    private static let usageBrightnessDownTopCase: UInt32 = 0x05

    // Debounce: avoid handling the same key press from multiple matching elements
    private var lastEventTime: TimeInterval = 0
    private var lastAction: MediaKeyAction?
    private let debounceInterval: TimeInterval = 0.03

    func start() {
        guard !isRunning else { return }

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            NSLog("[HIDKeyInterceptor] Failed to create IOHIDManager")
            return
        }

        let matchingKeyboards: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingKeyboards as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("[HIDKeyInterceptor] Failed to open IOHIDManager: 0x%X. "
                + "Grant Input Monitoring in System Settings > Privacy & Security > Input Monitoring.",
                  result)
            if result == IOReturn(bitPattern: 0xE00002E2) { // kIOReturnNotPermitted
                DispatchQueue.main.async {
                    HIDKeyInterceptor.promptInputMonitoring()
                }
            }
            return
        }

        isRunning = true
        NSLog("[HIDKeyInterceptor] Started. Listening for HID brightness/volume events.")
    }

    func stop() {
        guard isRunning, let manager = hidManager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        hidManager = nil
        isRunning = false
        NSLog("[HIDKeyInterceptor] Stopped.")
    }

    static func promptInputMonitoring() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Required"
        alert.informativeText = "Monitor Keyboard Fix needs Input Monitoring permission to intercept "
            + "brightness keys on Mac Studio/Mac Mini with external displays.\n\n"
            + "Please add this app in:\nSystem Settings > Privacy & Security > Input Monitoring"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private let hidInputCallback: IOHIDValueCallback = { context, result, sender, value in
        guard let context = context else { return }
        let interceptor = Unmanaged<HIDKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
        interceptor.handleHIDValue(value)
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Only handle key-down (value == 1)
        guard intValue == 1 else { return }

        var action: MediaKeyAction?

        switch (UInt32(usagePage), UInt32(usage)) {
        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageBrightnessUp),
             (HIDKeyInterceptor.usageAppleVendorTopCase, HIDKeyInterceptor.usageBrightnessUpTopCase):
            action = .brightnessUp

        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageBrightnessDown),
             (HIDKeyInterceptor.usageAppleVendorTopCase, HIDKeyInterceptor.usageBrightnessDownTopCase):
            action = .brightnessDown

        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageVolumeUp):
            action = .volumeUp

        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageVolumeDown):
            action = .volumeDown

        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageMute):
            action = .mute

        case (HIDKeyInterceptor.usageKeyboardPage, HIDKeyInterceptor.usageF14):
            action = .brightnessDown

        case (HIDKeyInterceptor.usageKeyboardPage, HIDKeyInterceptor.usageF15):
            action = .brightnessUp

        default:
            return
        }

        guard let action = action else { return }

        // For brightness: only handle if CGEvent tap is NOT handling them
        if action == .brightnessUp || action == .brightnessDown {
            if cgEventTapHandlesBrightness {
                return
            }
        }

        // For volume/mute: always defer to CGEvent tap (system handles these correctly)
        if action == .volumeUp || action == .volumeDown || action == .mute {
            return
        }

        // Debounce to avoid duplicate events from multiple matching HID elements
        let now = ProcessInfo.processInfo.systemUptime
        if action == lastAction && (now - lastEventTime) < debounceInterval {
            return
        }
        lastEventTime = now
        lastAction = action

        NSLog("[HIDKeyInterceptor] Action: %@ (usagePage=0x%X usage=0x%X)",
              String(describing: action), usagePage, usage)

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.handleMediaKey(action)
        }
    }
}
