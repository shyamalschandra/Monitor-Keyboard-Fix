import Foundation

enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast   = 0x12
    case volume     = 0x62
    case mute       = 0x8D
    case inputSource = 0x60
    case powerMode  = 0xD6

    var displayName: String {
        switch self {
        case .brightness:  return "Brightness"
        case .contrast:    return "Contrast"
        case .volume:      return "Volume"
        case .mute:        return "Mute"
        case .inputSource: return "Input Source"
        case .powerMode:   return "Power Mode"
        }
    }

    var maxValue: UInt16 {
        switch self {
        case .brightness, .contrast, .volume:
            return 100
        case .mute:
            return 2  // 1 = muted, 2 = unmuted
        case .inputSource:
            return 0xFF
        case .powerMode:
            return 0x05
        }
    }
}

struct VCPReply {
    let code: VCPCode
    let currentValue: UInt16
    let maxValue: UInt16
}
