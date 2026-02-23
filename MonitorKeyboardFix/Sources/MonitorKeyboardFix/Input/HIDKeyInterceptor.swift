import Foundation
import IOKit
import IOKit.hid
import AppKit

/// Intercepts brightness HID key events directly from the keyboard hardware via
/// IOHIDManager. This approach works even when macOS consumes the SystemDefined
/// events at the WindowServer level (common on Mac Studio/Mac Mini with only
/// external USB-C displays running macOS Sonoma+).
///
/// Apple keyboards report brightness on the vendor-specific page 0xFF01
/// (kHIDPage_AppleVendorKeyboard), NOT the standard Consumer page 0x0C.
/// The ioreg FnFunctionUsageMap confirms:
///   F1 -> 0xff010021 (brightness down)
///   F2 -> 0xff010020 (brightness up)
final class HIDKeyInterceptor {

    weak var delegate: MediaKeyDelegate?

    private var hidManager: IOHIDManager?
    private(set) var isRunning = false

    /// Tracks whether CGEvent-based KeyInterceptor has received brightness events.
    /// If it has, HID interceptor defers to it to avoid double-handling.
    var cgEventTapHandlesBrightness = false

    // Apple Vendor Keyboard Page (0xFF01) — what Apple keyboards actually report
    private static let usageAppleVendorKeyboardPage: UInt32 = 0xFF01
    private static let usageAppleVendorBrightnessUp: UInt32 = 0x0020
    private static let usageAppleVendorBrightnessDown: UInt32 = 0x0021

    // Standard Consumer Page (0x0C) — fallback for third-party USB keyboards
    private static let usageConsumerPage: UInt32 = 0x0C
    private static let usageConsumerBrightnessUp: UInt32 = 0x006F
    private static let usageConsumerBrightnessDown: UInt32 = 0x0070

    // Keyboard Page (0x07) — F14/F15 used as brightness on some configs
    private static let usageKeyboardPage: UInt32 = 0x07
    private static let usageF14: UInt32 = 0x69
    private static let usageF15: UInt32 = 0x6A

    private var lastEventTime: TimeInterval = 0
    private var lastAction: MediaKeyAction?
    private let debounceInterval: TimeInterval = 0.015

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
            [
                kIOHIDDeviceUsagePageKey: 0xFF01,   // Apple Vendor Keyboard
                kIOHIDDeviceUsageKey: 0x0001
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingKeyboards as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("[HIDKeyInterceptor] Failed to open IOHIDManager: 0x%X. "
                + "Grant Input Monitoring in System Settings > Privacy & Security > Input Monitoring.",
                  result)
            if result == IOReturn(bitPattern: 0xE00002E2) {
                DispatchQueue.main.async {
                    HIDKeyInterceptor.promptInputMonitoring()
                }
            }
            return
        }

        isRunning = true
        NSLog("[HIDKeyInterceptor] Started. Listening for Apple Vendor Keyboard page 0xFF01 brightness events.")
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

    // MARK: - Device Matching Callback

    private let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        NSLog("[HIDKeyInterceptor] Matched device: %@ (vendorID=0x%04X productID=0x%04X)",
              product, vendorID, productID)
    }

    // MARK: - Input Value Callback

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

        guard intValue == 1 else { return }

        var action: MediaKeyAction?

        switch (UInt32(usagePage), UInt32(usage)) {
        // Apple Vendor Keyboard page — primary path for Apple keyboards
        case (HIDKeyInterceptor.usageAppleVendorKeyboardPage, HIDKeyInterceptor.usageAppleVendorBrightnessUp):
            action = .brightnessUp

        case (HIDKeyInterceptor.usageAppleVendorKeyboardPage, HIDKeyInterceptor.usageAppleVendorBrightnessDown):
            action = .brightnessDown

        // Standard Consumer page — fallback for third-party USB keyboards
        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageConsumerBrightnessUp):
            action = .brightnessUp

        case (HIDKeyInterceptor.usageConsumerPage, HIDKeyInterceptor.usageConsumerBrightnessDown):
            action = .brightnessDown

        // F14/F15 — alternative brightness keys on some keyboard configurations
        case (HIDKeyInterceptor.usageKeyboardPage, HIDKeyInterceptor.usageF14):
            action = .brightnessDown

        case (HIDKeyInterceptor.usageKeyboardPage, HIDKeyInterceptor.usageF15):
            action = .brightnessUp

        default:
            return
        }

        guard let action = action else { return }

        if cgEventTapHandlesBrightness {
            return
        }

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
