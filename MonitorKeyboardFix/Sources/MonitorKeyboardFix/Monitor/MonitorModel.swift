import Foundation
import CoreGraphics

/// Represents a single external monitor with DDC/CI control capabilities.
/// All @Published state mutations happen on the main thread for thread safety.
/// DDC I2C commands are dispatched to a serial background queue.
final class MonitorModel: Identifiable, ObservableObject {
    let id: CGDirectDisplayID
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: String
    let ddcController: DDCController

    @Published var brightness: UInt16 = 50
    @Published var volume: UInt16 = 50
    @Published var isMuted: Bool = false
    @Published var hasReadInitialState: Bool = false

    /// Serial queue for DDC I2C commands to this monitor. Serialized to avoid
    /// concurrent I2C writes on the same bus which corrupt each other.
    private let ddcQueue: DispatchQueue

    init(displayID: CGDirectDisplayID, name: String, vendorID: UInt32,
         productID: UInt32, serialNumber: String, ddcController: DDCController) {
        self.id = displayID
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.ddcController = ddcController
        self.ddcQueue = DispatchQueue(label: "com.mkf.ddc.\(displayID)", qos: .userInitiated)
    }

    // MARK: - DDC Read (call from background only)

    func readCurrentValues() {
        if let brightnessReply = ddcController.getVCP(.brightness) {
            let val = brightnessReply.currentValue
            DispatchQueue.main.async { self.brightness = val }
        }
        if let volumeReply = ddcController.getVCP(.volume) {
            let val = volumeReply.currentValue
            DispatchQueue.main.async { self.volume = val }
        }
        DispatchQueue.main.async { self.hasReadInitialState = true }
    }

    // MARK: - Brightness

    /// Adjust brightness by a step. Updates local state immediately on the
    /// calling thread (must be main), then sends DDC command in background.
    func adjustBrightness(by step: Int16) {
        let newValue = Int32(brightness) + Int32(step)
        let clamped = UInt16(max(0, min(100, newValue)))
        brightness = clamped
        let controller = ddcController
        ddcQueue.async {
            controller.setVCP(.brightness, value: clamped)
        }
    }

    func setBrightness(_ value: UInt16) {
        let clamped = min(value, 100)
        brightness = clamped
        let controller = ddcController
        ddcQueue.async {
            controller.setVCP(.brightness, value: clamped)
        }
    }

    // MARK: - Volume

    func adjustVolume(by step: Int16) {
        let newValue = Int32(volume) + Int32(step)
        let clamped = UInt16(max(0, min(100, newValue)))
        volume = clamped
        if clamped > 0 { isMuted = false }
        let controller = ddcController
        ddcQueue.async {
            controller.setVCP(.volume, value: clamped)
        }
    }

    func setVolume(_ value: UInt16) {
        let clamped = min(value, 100)
        volume = clamped
        if clamped > 0 { isMuted = false }
        let controller = ddcController
        ddcQueue.async {
            controller.setVCP(.volume, value: clamped)
        }
    }

    // MARK: - Mute

    func toggleMute() {
        let willMute = !isMuted
        isMuted = willMute
        let ddcValue: UInt16 = willMute ? 1 : 2
        let controller = ddcController
        ddcQueue.async {
            controller.setVCP(.mute, value: ddcValue)
        }
    }

    var displayDescription: String {
        "\(name) (ID: \(id), Vendor: \(String(vendorID, radix: 16)), Product: \(String(productID, radix: 16)))"
    }
}
