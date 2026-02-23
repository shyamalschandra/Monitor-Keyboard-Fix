import Foundation
import CoreGraphics

/// Represents a single external monitor with DDC/CI control capabilities.
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

    /// Track whether we've successfully read initial values from the monitor.
    @Published var hasReadInitialState: Bool = false

    init(displayID: CGDirectDisplayID, name: String, vendorID: UInt32,
         productID: UInt32, serialNumber: String, ddcController: DDCController) {
        self.id = displayID
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.ddcController = ddcController
    }

    // MARK: - DDC Read

    func readCurrentValues() {
        if let brightnessReply = ddcController.getVCP(.brightness) {
            brightness = brightnessReply.currentValue
        }
        if let volumeReply = ddcController.getVCP(.volume) {
            volume = volumeReply.currentValue
        }
        hasReadInitialState = true
    }

    // MARK: - DDC Write

    func setBrightness(_ value: UInt16) {
        let clamped = min(value, 100)
        if ddcController.setVCP(.brightness, value: clamped) {
            brightness = clamped
        }
    }

    func setVolume(_ value: UInt16) {
        let clamped = min(value, 100)
        if ddcController.setVCP(.volume, value: clamped) {
            volume = clamped
            if clamped > 0 { isMuted = false }
        }
    }

    func toggleMute() {
        let newMuteValue: UInt16 = isMuted ? 2 : 1  // 1 = muted, 2 = unmuted
        if ddcController.setVCP(.mute, value: newMuteValue) {
            isMuted = !isMuted
        }
    }

    // MARK: - Adjust by Step

    func adjustBrightness(by step: Int16) {
        let newValue = Int32(brightness) + Int32(step)
        let clamped = UInt16(max(0, min(100, newValue)))
        setBrightness(clamped)
    }

    func adjustVolume(by step: Int16) {
        let newValue = Int32(volume) + Int32(step)
        let clamped = UInt16(max(0, min(100, newValue)))
        setVolume(clamped)
    }

    var displayDescription: String {
        "\(name) (ID: \(id), Vendor: \(String(vendorID, radix: 16)), Product: \(String(productID, radix: 16)))"
    }
}
