import Foundation

/// 首页所有可观察状态，等价于原小程序 Page({ data: {...} })
struct WingUIState {
    var mode: WingMode = .daily

    // 手动升降
    var step: Int = 0

    // 自动升降
    var isAuto: Bool = false
    var downIndex: Int = WingProtocol.defaultDownIndex
    var upIndex: Int = WingProtocol.defaultUpIndex

    // 赛道模式
    var trackType: Int = 2

    // 点火升降
    var ignitionOn: Bool = false
    var ignitionReady: Bool = false

    // 设备上报
    var speed: Int = 0
    var isDescending: Bool = false
    var isFirstReception: Bool = true

    var downSpeed: Int { WingProtocol.downSpeeds[downIndex] }
    var upSpeed: Int { WingProtocol.upSpeeds[upIndex] }
    var intensity: Int { WingProtocol.intensity(for: trackType) }
    var ignitionTitle: String { WingProtocol.ignitionTitle(ready: ignitionReady, on: ignitionOn) }
    var stepAsset: String { WingProtocol.assetName(forStep: step) }
}

/// 统一用 alert(item:) 呈现，避免同层级多个 alert 冲突
enum WingAlertItem: Identifiable {
    case info(String)
    case calibration

    var id: String {
        switch self {
        case .info(let text): return "info-\(text)"
        case .calibration:    return "calibration"
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let text: String
}

/// 以 sheet 呈现的弹层。sheet 自带下滑关闭手势，界面内另提供显式关闭按钮。
enum WingSheet: String, Identifiable, CaseIterable {
    case autoHint
    case trackHint
    case ignitionSuccess
    case ignitionFailure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoHint:         return "自动升降模式"
        case .trackHint:        return "赛道模式"
        case .ignitionSuccess:  return "点火升降 操作成功"
        case .ignitionFailure:  return "点火升降 操作失败"
        }
    }
}
