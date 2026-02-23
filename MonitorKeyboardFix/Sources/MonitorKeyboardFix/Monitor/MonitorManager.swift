import Foundation
import IOKit
import CoreGraphics
import AppKit
import IOAVServiceBridge

/// Discovers and manages external Dell monitors via IOKit.
/// Creates IOAVService handles for each external display and pairs them
/// with CGDirectDisplayID by testing DDC/CI readability.
final class MonitorManager: ObservableObject {

    @Published var monitors: [MonitorModel] = []

    var stepSize: UInt16 = 6

    static let dellVendorID: UInt32 = 0x10AC

    func discoverMonitors() {
        monitors.removeAll()

        let externalDisplayIDs = getExternalDisplayIDs()
        NSLog("[MonitorManager] Found %d external CG display(s).", externalDisplayIDs.count)

        let avServices = getAllIOAVServices()
        NSLog("[MonitorManager] Found %d IOAVService handle(s).", avServices.count)

        if externalDisplayIDs.isEmpty {
            NSLog("[MonitorManager] No external displays detected by CoreGraphics.")
            return
        }

        if avServices.isEmpty {
            NSLog("[MonitorManager] No IOAVService handles found. DDC/CI will not work.")
            return
        }

        // Strategy: For each external display, try each IOAVService handle.
        // Use the first handle that successfully responds to a DDC brightness read.
        // If none respond, assign handles round-robin and rely on write-only mode.
        var usedServiceIndices = Set<Int>()

        for displayID in externalDisplayIDs {
            let info = getDisplayInfo(for: displayID)
            NSLog("[MonitorManager] Pairing display: %@ (CG ID %d, vendor 0x%X, product 0x%X)",
                  info.name, displayID, info.vendorID, info.productID)

            var pairedService: UnsafeMutableRawPointer?
            var pairedIndex: Int?

            // Try each unused service to find one that responds to DDC
            for (index, service) in avServices.enumerated() {
                if usedServiceIndices.contains(index) { continue }
                let testController = DDCController(service: service)
                if let reply = testController.getVCP(.brightness) {
                    NSLog("[MonitorManager] Service %d responded: brightness=%d/%d",
                          index, reply.currentValue, reply.maxValue)
                    pairedService = service
                    pairedIndex = index
                    break
                } else {
                    NSLog("[MonitorManager] Service %d did not respond to DDC read.", index)
                }
            }

            // Fallback: use first unused service even if it didn't respond to read
            if pairedService == nil {
                for (index, service) in avServices.enumerated() {
                    if usedServiceIndices.contains(index) { continue }
                    NSLog("[MonitorManager] Fallback: assigning service %d to display %d (write-only mode).", index, displayID)
                    pairedService = service
                    pairedIndex = index
                    break
                }
            }

            guard let service = pairedService else {
                NSLog("[MonitorManager] No available IOAVService for display %d. Skipping.", displayID)
                continue
            }

            if let idx = pairedIndex {
                usedServiceIndices.insert(idx)
            }

            let controller = DDCController(service: service)
            let monitor = MonitorModel(
                displayID: displayID,
                name: info.name,
                vendorID: info.vendorID,
                productID: info.productID,
                serialNumber: info.serial,
                ddcController: controller
            )
            monitors.append(monitor)
            NSLog("[MonitorManager] Paired: %@", monitor.displayDescription)
        }

        // Read initial state on background threads
        for monitor in monitors {
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.readCurrentValues()
                NSLog("[MonitorManager] Initial state for %@: brightness=%d volume=%d readOK=%d",
                      monitor.name, monitor.brightness, monitor.volume,
                      monitor.hasReadInitialState ? 1 : 0)
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

    private func getAllIOAVServices() -> [UnsafeMutableRawPointer] {
        var services: [UnsafeMutableRawPointer] = []

        // Try DCPAVServiceProxy first (modern Apple Silicon path)
        services = enumerateServices(className: "DCPAVServiceProxy")

        if services.isEmpty {
            NSLog("[MonitorManager] No DCPAVServiceProxy found, trying AppleCLCD2.")
            services = enumerateServices(className: "AppleCLCD2")
        }

        // Last resort: the global IOAVServiceCreate (only returns one service)
        if services.isEmpty {
            NSLog("[MonitorManager] Trying global IOAVServiceCreate.")
            if let globalService = mkf_IOAVServiceCreate(kCFAllocatorDefault) {
                services.append(globalService)
            }
        }

        return services
    }

    private func enumerateServices(className: String) -> [UnsafeMutableRawPointer] {
        var services: [UnsafeMutableRawPointer] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(className)
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == kIOReturnSuccess else {
            NSLog("[MonitorManager] IOServiceGetMatchingServices(%@) failed: 0x%X", className, result)
            return services
        }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let avService = mkf_IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                services.append(avService)
                NSLog("[MonitorManager] Created IOAVService from %@ (io_service_t=%d)", className, service)
            } else {
                NSLog("[MonitorManager] mkf_IOAVServiceCreateWithService returned nil for %@ (io_service_t=%d)", className, service)
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

        let externals = (0..<Int(displayCount)).compactMap { i -> CGDirectDisplayID? in
            let id = displayIDs[i]
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            NSLog("[MonitorManager] CG Display %d: id=%d builtin=%d", i, id, isBuiltin ? 1 : 0)
            return isBuiltin ? nil : id
        }

        return externals
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
}

// MARK: - CoreDisplay Private API

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> Unmanaged<CFDictionary>?
