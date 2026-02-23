import Foundation
import IOKit
import IOAVServiceBridge

/// Low-level DDC/CI controller using IOAVService I2C on Apple Silicon.
/// Wraps the private IOAVServiceWriteI2C/ReadI2C APIs with retry logic.
final class DDCController {

    static let chipAddress: UInt32 = 0x37   // DDC/CI 7-bit I2C address
    static let dataAddress: UInt32 = 0x51

    struct TimingConfig {
        var writeSleepMicroseconds: UInt32 = 10_000   // 10ms between writes
        var readSleepMicroseconds: UInt32 = 50_000    // 50ms before read after write
        var retrySleepMicroseconds: UInt32 = 20_000   // 20ms between retries
        var maxRetries: Int = 4
        var writeCycles: Int = 2
    }

    let service: UnsafeMutableRawPointer
    var timing = TimingConfig()

    init(service: UnsafeMutableRawPointer) {
        self.service = service
    }

    // MARK: - Set VCP Value

    @discardableResult
    func setVCP(_ code: VCPCode, value: UInt16) -> Bool {
        var packet = DDCPacket.buildSetPacket(code: code, value: value)
        NSLog("[DDC] setVCP %@ = %d (packet: %@)", code.displayName, value,
              packet.map { String(format: "%02X", $0) }.joined(separator: " "))
        let ok = writeI2C(&packet)
        NSLog("[DDC] setVCP %@ = %d -> %@", code.displayName, value, ok ? "OK" : "FAILED")
        return ok
    }

    // MARK: - Get VCP Value

    func getVCP(_ code: VCPCode) -> VCPReply? {
        var packet = DDCPacket.buildGetPacket(code: code)
        NSLog("[DDC] getVCP %@ (packet: %@)", code.displayName,
              packet.map { String(format: "%02X", $0) }.joined(separator: " "))

        for attempt in 0..<timing.maxRetries {
            let writeOK = writeI2CRaw(&packet)
            guard writeOK else {
                NSLog("[DDC] getVCP %@ attempt %d: write failed", code.displayName, attempt)
                usleep(timing.retrySleepMicroseconds)
                continue
            }

            usleep(timing.readSleepMicroseconds)

            var reply = [UInt8](repeating: 0, count: 11)
            let readResult = mkf_IOAVServiceReadI2C(
                service,
                DDCController.chipAddress,
                0,
                &reply,
                UInt32(reply.count)
            )

            let readHex = reply.map { String(format: "%02X", $0) }.joined(separator: " ")

            if readResult == kIOReturnSuccess {
                NSLog("[DDC] getVCP %@ attempt %d: read OK, data: %@", code.displayName, attempt, readHex)
                if let parsed = DDCPacket.parseGetReply(code: code, data: reply) {
                    NSLog("[DDC] getVCP %@ = %d (max %d)", code.displayName, parsed.currentValue, parsed.maxValue)
                    return parsed
                } else {
                    NSLog("[DDC] getVCP %@ attempt %d: parse failed (checksum or format)", code.displayName, attempt)
                }
            } else {
                NSLog("[DDC] getVCP %@ attempt %d: read failed (0x%X), data: %@",
                      code.displayName, attempt, readResult, readHex)
            }

            usleep(timing.retrySleepMicroseconds)
        }

        NSLog("[DDC] getVCP %@ FAILED after %d attempts", code.displayName, timing.maxRetries)
        return nil
    }

    // MARK: - Private I2C Helpers

    private func writeI2C(_ data: inout [UInt8]) -> Bool {
        for retry in 0..<timing.maxRetries {
            var success = false
            for cycle in 0..<timing.writeCycles {
                usleep(timing.writeSleepMicroseconds)
                let result = mkf_IOAVServiceWriteI2C(
                    service,
                    DDCController.chipAddress,
                    DDCController.dataAddress,
                    &data,
                    UInt32(data.count)
                )
                if result == kIOReturnSuccess {
                    success = true
                } else {
                    NSLog("[DDC] writeI2C retry=%d cycle=%d failed: 0x%X", retry, cycle, result)
                }
            }
            if success { return true }
            usleep(timing.retrySleepMicroseconds)
        }
        return false
    }

    private func writeI2CRaw(_ data: inout [UInt8]) -> Bool {
        usleep(timing.writeSleepMicroseconds)
        let result = mkf_IOAVServiceWriteI2C(
            service,
            DDCController.chipAddress,
            DDCController.dataAddress,
            &data,
            UInt32(data.count)
        )
        return result == kIOReturnSuccess
    }
}
