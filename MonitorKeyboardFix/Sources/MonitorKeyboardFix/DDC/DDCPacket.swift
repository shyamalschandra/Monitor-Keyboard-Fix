import Foundation

/// DDC/CI packet construction and checksum computation per the VESA MCCS standard.
enum DDCPacket {

    static let sourceAddress: UInt8 = 0x51
    static let destinationWriteAddress: UInt8 = 0x6E

    // MARK: - VCP Set (write a value to a VCP feature)

    static func buildSetPacket(code: VCPCode, value: UInt16) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 6)
        data[0] = 0x84  // length: 4 bytes following (excluding checksum)
        data[1] = 0x03  // VCP Set opcode
        data[2] = code.rawValue
        data[3] = UInt8((value >> 8) & 0xFF)  // value high byte
        data[4] = UInt8(value & 0xFF)          // value low byte
        data[5] = computeChecksum(initialXOR: destinationWriteAddress ^ sourceAddress,
                                  data: data, start: 0, end: 4)
        return data
    }

    // MARK: - VCP Get (request current value of a VCP feature)

    static func buildGetPacket(code: VCPCode) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        data[0] = 0x82  // length: 2 bytes following (excluding checksum)
        data[1] = 0x01  // VCP Get opcode
        data[2] = code.rawValue
        data[3] = computeChecksum(initialXOR: destinationWriteAddress ^ sourceAddress,
                                  data: data, start: 0, end: 2)
        return data
    }

    // MARK: - Parse VCP Get Reply

    /// Parse a VCP Get reply from the monitor. Returns nil if checksum fails or format is unexpected.
    static func parseGetReply(code: VCPCode, data: [UInt8]) -> VCPReply? {
        // Expected reply format (11 bytes from data address 0x51):
        // [0] = source (0x6E)
        // [1] = length byte (0x88 = 8 bytes following)
        // [2] = 0x02 (VCP reply opcode)
        // [3] = result code (0x00 = no error)
        // [4] = VCP code
        // [5] = type byte
        // [6] = max value high byte
        // [7] = max value low byte
        // [8] = current value high byte
        // [9] = current value low byte
        // [10] = checksum

        guard data.count >= 11 else { return nil }

        let expectedChecksum = computeChecksum(initialXOR: 0x50,
                                               data: data, start: 0, end: data.count - 2)
        guard data[data.count - 1] == expectedChecksum else { return nil }
        guard data[2] == 0x02 else { return nil }
        guard data[3] == 0x00 else { return nil }
        guard data[4] == code.rawValue else { return nil }

        let maxValue = (UInt16(data[6]) << 8) | UInt16(data[7])
        let currentValue = (UInt16(data[8]) << 8) | UInt16(data[9])

        return VCPReply(code: code, currentValue: currentValue, maxValue: maxValue)
    }

    // MARK: - Checksum

    private static func computeChecksum(initialXOR: UInt8, data: [UInt8],
                                         start: Int, end: Int) -> UInt8 {
        var checksum = initialXOR
        for i in start...end {
            checksum ^= data[i]
        }
        return checksum
    }
}
