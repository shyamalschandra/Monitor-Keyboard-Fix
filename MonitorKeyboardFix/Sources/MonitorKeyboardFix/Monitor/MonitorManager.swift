import Foundation
import IOKit
import CoreGraphics
import AppKit
import IOAVServiceBridge

/// Discovers and manages external Dell monitors via IOKit.
/// Enumerates AppleCLCD2 nodes on Apple Silicon and creates DDCController instances.
final class MonitorManager: ObservableObject {

    @Published var monitors: [MonitorModel] = []

    /// Step size for brightness/volume changes per key press (out of 100).
    var stepSize: UInt16 = 6

    // Dell EDID vendor code: "DEL" encoded as EISA 3-char ID = 0x10AC
    static let dellVendorID: UInt32 = 0x10AC

    func discoverMonitors() {
        monitors.removeAll()

        let externalDisplayIDs = getExternalDisplayIDs()
        let avServices = getIOAVServices()

        for (displayID, avService) in zip(externalDisplayIDs, avServices) {
            let info = getDisplayInfo(for: displayID)
            let controller = DDCController(service: avService)
            let monitor = MonitorModel(
                displayID: displayID,
                name: info.name,
                vendorID: info.vendorID,
                productID: info.productID,
                serialNumber: info.serial,
                ddcController: controller
            )
            monitors.append(monitor)
            NSLog("[MonitorManager] Found: %@", monitor.displayDescription)
        }

        if monitors.isEmpty {
            NSLog("[MonitorManager] No external monitors found. Falling back to all active displays.")
            discoverFallback()
        }

        for monitor in monitors {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.readCurrentValues()
                NSLog("[MonitorManager] %@ brightness=%d volume=%d",
                      monitor.name, monitor.brightness, monitor.volume)
            }
        }
    }

    // MARK: - Brightness / Volume Control for All Monitors

    func adjustBrightnessAll(by step: Int16) {
        for monitor in monitors {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.adjustBrightness(by: step)
            }
        }
    }

    func adjustVolumeAll(by step: Int16) {
        for monitor in monitors {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.adjustVolume(by: step)
            }
        }
    }

    func toggleMuteAll() {
        for monitor in monitors {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.toggleMute()
            }
        }
    }

    var averageBrightness: UInt16 {
        guard !monitors.isEmpty else { return 0 }
        let total = monitors.reduce(0) { $0 + Int($1.brightness) }
        return UInt16(total / monitors.count)
    }

    var averageVolume: UInt16 {
        guard !monitors.isEmpty else { return 0 }
        let total = monitors.reduce(0) { $0 + Int($1.volume) }
        return UInt16(total / monitors.count)
    }

    // MARK: - IOAVService Enumeration (Apple Silicon)

    private func getIOAVServices() -> [UnsafeMutableRawPointer] {
        var services: [UnsafeMutableRawPointer] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == kIOReturnSuccess else {
            NSLog("[MonitorManager] Failed to find DCPAVServiceProxy services: %d", result)
            return getIOAVServicesLegacy()
        }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let avService = mkf_IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                services.append(avService)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        if services.isEmpty {
            return getIOAVServicesLegacy()
        }

        return services
    }

    private func getIOAVServicesLegacy() -> [UnsafeMutableRawPointer] {
        var services: [UnsafeMutableRawPointer] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleCLCD2")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == kIOReturnSuccess else {
            NSLog("[MonitorManager] Failed to find AppleCLCD2 services: %d", result)
            return services
        }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let avService = mkf_IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                services.append(avService)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        return services
    }

    // MARK: - CoreGraphics Display Enumeration

    private func getExternalDisplayIDs() -> [CGDirectDisplayID] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        return (0..<Int(displayCount)).compactMap { i in
            let id = displayIDs[i]
            if CGDisplayIsBuiltin(id) == 0 {
                return id
            }
            return nil
        }
    }

    private struct DisplayInfo {
        var name: String
        var vendorID: UInt32
        var productID: UInt32
        var serial: String
    }

    private func getDisplayInfo(for displayID: CGDirectDisplayID) -> DisplayInfo {
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let serial = String(CGDisplaySerialNumber(displayID))

        var name = "External Display"

        if let infoDict = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as? [String: Any] {
            if let names = infoDict["DisplayProductName"] as? [String: String],
               let enName = names["en_US"] ?? names.values.first {
                name = enName
            }
        }

        return DisplayInfo(name: name, vendorID: vendorID, productID: productID, serial: serial)
    }

    // MARK: - Fallback

    private func discoverFallback() {
        let externalIDs = getExternalDisplayIDs()
        let avServices = getIOAVServices()

        for (index, displayID) in externalIDs.enumerated() {
            let info = getDisplayInfo(for: displayID)

            let service: UnsafeMutableRawPointer?
            if index < avServices.count {
                service = avServices[index]
            } else if let first = avServices.first {
                service = first
            } else {
                service = mkf_IOAVServiceCreate(kCFAllocatorDefault)
            }

            guard let avService = service else {
                NSLog("[MonitorManager] No IOAVService available for display %d", displayID)
                continue
            }

            let controller = DDCController(service: avService)
            let monitor = MonitorModel(
                displayID: displayID,
                name: info.name,
                vendorID: info.vendorID,
                productID: info.productID,
                serialNumber: info.serial,
                ddcController: controller
            )
            monitors.append(monitor)
            NSLog("[MonitorManager] Fallback found: %@", monitor.displayDescription)
        }
    }
}

// MARK: - CoreDisplay Private API

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> Unmanaged<CFDictionary>?
