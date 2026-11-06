import Foundation

// MARK: - 模式

/// 小程序首页顶部的两个页签：日常模式 / 赛道模式
enum WingMode: String, CaseIterable, Identifiable, Hashable {
    case daily = "日常模式"
    case track = "赛道模式"

    var id: String { rawValue }
}

// MARK: - 指令

/// 与原小程序 `pages/index/index.js` 中拼接的 g = "BB" + did + "80..." 一一对应
enum WingCommand {
    case setStep(Int)              // 8001 + 档位 + 00
    case auto(down: Int, up: Int)  // 8002 + 降速临界 + 升速临界
    case autoOff                   // 8003 00 00
    case track(Int)                // 8004 + 1/2/3 + 00
    case ignition(Bool)            // 8005 + 0/1 + 00
    case oneKey(up: Bool)          // 8006 01/02 00

    var displayName: String {
        switch self {
        case .setStep(let s):        return "设置档位 \(s)"
        case .auto(let d, let u):    return "自动升降 \(d)/\(u) km/h"
        case .autoOff:               return "关闭自动升降"
        case .track(let t):          return "赛道灵敏度 \(t)"
        case .ignition(let on):      return on ? "开启点火升降" : "关闭点火升降"
        case .oneKey(let up):        return up ? "一键上升" : "一键下降"
        }
    }
}

// MARK: - 速度校验结果

enum SpeedValidation {
    case valid
    case calibration
    case invalid(String)
}

// MARK: - 设备上报状态

/// 通知特征值返回的 8 字节基础帧 / 12 字节扩展帧
struct WingTelemetry {
    let autoFlag: Int
    let step: Int
    let speed: Int
    let downSpeed: Int
    let upSpeed: Int
    let trackType: Int?
    let ignitionOn: Bool?
    let ignitionReady: Bool?
    let fireResult: Int?
}

// MARK: - 协议

enum WingProtocol {

    /// 原小程序 picker-view 两列数据
    static let downSpeeds: [Int] = [0, 10, 20, 30, 40, 50, 60, 70, 80]
    static let upSpeeds: [Int]   = [0, 50, 60, 70, 80, 90, 100, 110, 120]

    /// 设备只有 4 档：0 / 3 / 4 / 5，对应 tial0/3/4/5.png
    static let selectableSteps: [Int] = [0, 3, 4, 5]

    static let defaultDownIndex = 1   // 10 km/h
    static let defaultUpIndex   = 4   // 80 km/h

    private static let header: UInt8 = 0xBB
    private static let fixed: UInt8  = 0x80

    /// 与 `bindChangeleft` 中的四条校验规则保持一致（含顺序）
    static func validate(down: Int, up: Int) -> SpeedValidation {
        if down == 0 && up == 0 { return .calibration }
        if up < down + 20 { return .invalid("降速加速临界范围总大于20码") }
        if down == 0 && up != 0 { return .invalid("下降速度必须大于零，升降都为零校准除外") }
        if up <= down { return .invalid("升起速度必须大于下降速度，升降都为零校准除外") }
        return .valid
    }

    /// 构造 6 字节指令帧：BB | did | 80 | cmd | p1 | p2
    static func frame(_ command: WingCommand, deviceID: UInt8) -> Data {
        var bytes: [UInt8] = [header, deviceID, fixed]
        switch command {
        case .setStep(let step):
            bytes += [0x01, UInt8(step & 0xFF), 0x00]
        case .auto(let down, let up):
            bytes += [0x02, UInt8(down & 0xFF), UInt8(up & 0xFF)]
        case .autoOff:
            bytes += [0x03, 0x00, 0x00]
        case .track(let type):
            bytes += [0x04, UInt8(type & 0xFF), 0x00]
        case .ignition(let on):
            bytes += [0x05, on ? 0x01 : 0x00, 0x00]
        case .oneKey(let up):
            bytes += [0x06, up ? 0x01 : 0x02, 0x00]
        }
        return Data(bytes)
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// 解析 notify 数据。字节 3~7 为基础状态，字节 8~11 为扩展状态。
    static func parse(_ data: Data) -> WingTelemetry? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        let extended = bytes.count >= 12
        return WingTelemetry(
            autoFlag: Int(bytes[3]),
            step: Int(bytes[4]),
            speed: Int(bytes[5]),
            downSpeed: Int(bytes[6]),
            upSpeed: Int(bytes[7]),
            trackType: extended ? Int(bytes[8]) : nil,
            ignitionOn: extended ? (bytes[9] == 1) : nil,
            ignitionReady: extended ? (bytes[10] == 1) : nil,
            fireResult: extended ? Int(bytes[11]) : nil
        )
    }

    /// 强 = -2 / 中 = -3 / 弱 = -5 (m/s²)，对应原 `changeTrackType` 的 intensity
    static func intensity(for trackType: Int) -> Int {
        switch trackType {
        case 1: return -2
        case 2: return -3
        case 3: return -5
        default: return -3
        }
    }

    static func ignitionTitle(ready: Bool, on: Bool) -> String {
        if !ready { return "点火升降(需配合车内按键)" }
        return on ? "点火升降(已开启)" : "点火升降(已关闭)"
    }

    static func assetName(forStep step: Int) -> String {
        let valid = selectableSteps.last(where: { $0 <= step }) ?? 0
        return "Wing\(valid)"
    }
}
