import Foundation
import CoreGraphics

/// Represents a single external monitor with DDC/CI control capabilities.
/// State updates are optimistic: the local brightness/volume values are updated
/// immediately so the OSD is responsive, regardless of whether the DDC command
/// actually succeeded on the wire.
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

    // MARK: - DDC Write (optimistic)

    func setBrightness(_ value: UInt16) {
        let clamped = min(value, 100)
        brightness = clamped
        ddcController.setVCP(.brightness, value: clamped)
    }

    func setVolume(_ value: UInt16) {
        let clamped = min(value, 100)
        volume = clamped
        if clamped > 0 { isMuted = false }
        ddcController.setVCP(.volume, value: clamped)
    }

    func toggleMute() {
        let willMute = !isMuted
        isMuted = willMute
        let ddcValue: UInt16 = willMute ? 1 : 2  // 1 = muted, 2 = unmuted
        ddcController.setVCP(.mute, value: ddcValue)
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
