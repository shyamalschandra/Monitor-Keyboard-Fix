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
        return writeI2C(&packet)
    }

    // MARK: - Get VCP Value

    func getVCP(_ code: VCPCode) -> VCPReply? {
        var packet = DDCPacket.buildGetPacket(code: code)

        for _ in 0..<timing.maxRetries {
            let writeOK = writeI2CRaw(&packet)
            guard writeOK else {
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

            if readResult == kIOReturnSuccess {
                if let parsed = DDCPacket.parseGetReply(code: code, data: reply) {
                    return parsed
                }
            }

            usleep(timing.retrySleepMicroseconds)
        }

        return nil
    }

    // MARK: - Private I2C Helpers

    private func writeI2C(_ data: inout [UInt8]) -> Bool {
        for _ in 0..<timing.maxRetries {
            var success = false
            for _ in 0..<timing.writeCycles {
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
