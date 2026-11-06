import Foundation
import Combine

/// 页面状态机：把原小程序 Page 的 data + 事件处理迁移到 ObservableObject
final class WingController: ObservableObject {

    @Published var state = WingUIState()
    @Published var logs: [LogEntry] = []
    @Published var sheet: WingSheet?
    @Published var alertItem: WingAlertItem?
    @Published var demoMode = false
    @Published var demoHardwareButtonInstalled = true
    /// 每次滚轮选择后自增，驱动自定义 UIPickerView 回弹到合法值
    @Published var speedPickerRevision = 0

    let ble = BLEManager()

    private let defaults = UserDefaults.standard
    private let deviceIDKey = "wing.deviceID"
    private let launchLogKey = "wing.launchLogs"
    private var deviceID: UInt8 = 0
    private var pendingIgnitionDesired: Bool?
    private var pendingCalibrationIndices: (Int, Int)?
    private var cancellable: AnyCancellable?

    init() {
        // 与原小程序一致：首次生成随机 did(0~255) 并缓存，之后所有指令复用
        if let saved = defaults.object(forKey: deviceIDKey) as? Int {
            deviceID = UInt8(saved & 0xFF)
        } else {
            deviceID = UInt8.random(in: UInt8.min ... UInt8.max)
            defaults.set(Int(deviceID), forKey: deviceIDKey)
        }

        #if targetEnvironment(simulator)
        // 模拟器没有 BLE，自动进入演示模式，便于无硬件验证全部交互
        demoMode = true
        #endif

        cancellable = ble.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        ble.onData = { [weak self] data in self?.handleReply(data) }
        ble.onLog = { [weak self] text in self?.appendLog(text) }
        ble.onDisconnect = { [weak self] in
            guard let self = self else { return }
            self.state.isFirstReception = true
            self.appendLog("设备断开，等待重新连接")
        }

        recordLaunch()
    }

    // MARK: - 连接状态（供界面使用）

    var isConnected: Bool { demoMode || ble.phase == .ready }

    var connectionText: String {
        if demoMode { return "演示模式（无需硬件）" }
        if case .ready = ble.phase, let name = ble.connectedName { return "已连接 · \(name)" }
        return ble.phase.displayText
    }

    // MARK: - 日志

    var launchLogs: [Date] {
        (defaults.array(forKey: launchLogKey) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
    }

    private func recordLaunch() {
        var values = defaults.array(forKey: launchLogKey) as? [Double] ?? []
        values.insert(Date().timeIntervalSince1970, at: 0)
        defaults.set(Array(values.prefix(50)), forKey: launchLogKey)
        appendLog("App 启动 · did=\(String(format: "%02X", deviceID))")
    }

    func appendLog(_ text: String) {
        logs.insert(LogEntry(date: Date(), text: text), at: 0)
        if logs.count > 200 { logs = Array(logs.prefix(200)) }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - 指令发送

    /// 先做乐观 UI 更新，再发送；未连接时给出明确提示而不是静默失败
    private func commit(_ command: WingCommand, optimistic: (() -> Void)? = nil) {
        optimistic?()
        Haptics.selection()
        let frame = WingProtocol.frame(command, deviceID: deviceID)

        guard isConnected else {
            alertItem = .info("您还没有连接尾翼设备，请先到「设备」页搜索并连接")
            appendLog("指令未发送（设备未连接）：\(command.displayName)")
            return
        }
        appendLog("发送 \(command.displayName) → \(WingProtocol.hexString(frame))")

        if demoMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.simulateReply(for: command)
            }
        } else {
            ble.write(frame)
        }
    }

    // MARK: - 用户操作

    func setMode(_ mode: WingMode) {
        state.mode = mode
        Haptics.selection()
    }

    func setAuto(_ enabled: Bool) {
        state.isAuto = enabled
        if enabled {
            commit(.auto(down: state.downSpeed, up: state.upSpeed))
        } else {
            state.downIndex = WingProtocol.defaultDownIndex
            state.upIndex = WingProtocol.defaultUpIndex
            commit(.autoOff)
        }
    }

    /// picker-view 两列变化；校验不通过时不写入 state，滚轮会回弹
    func updateSpeeds(downIndex: Int, upIndex: Int) {
        speedPickerRevision += 1
        let down = WingProtocol.downSpeeds[downIndex]
        let up = WingProtocol.upSpeeds[upIndex]
        switch WingProtocol.validate(down: down, up: up) {
        case .valid:
            state.downIndex = downIndex
            state.upIndex = upIndex
            commit(.auto(down: down, up: up))
        case .calibration:
            pendingCalibrationIndices = (downIndex, upIndex)
            alertItem = .calibration
        case .invalid(let message):
            alertItem = .info(message)
            Haptics.warning()
        }
    }

    /// 原小程序「两个 0」在校验顺序下难以通过逐列滚动到达，这里提供显式入口
    func requestCalibration() {
        pendingCalibrationIndices = (0, 0)
        alertItem = .calibration
    }

    func confirmCalibration() {
        guard let pair = pendingCalibrationIndices else { return }
        pendingCalibrationIndices = nil
        state.downIndex = pair.0
        state.upIndex = pair.1
        appendLog("进入校准模式（升降速度临界均设为 0）")
        commit(.auto(down: 0, up: 0))
    }

    func setStep(_ step: Int) {
        let valid = WingProtocol.selectableSteps.contains(step)
            ? step
            : (WingProtocol.selectableSteps.last(where: { $0 <= step }) ?? 0)
        commit(.setStep(valid)) { self.state.step = valid }
    }

    /// 原 addStepNum：0→3→4→5
    func stepUp() {
        let index = WingProtocol.selectableSteps.firstIndex(of: state.step) ?? 0
        let next = min(index + 1, WingProtocol.selectableSteps.count - 1)
        setStep(WingProtocol.selectableSteps[next])
    }

    /// 原 subStepNum：5→4→3→0
    func stepDown() {
        let index = WingProtocol.selectableSteps.firstIndex(of: state.step) ?? 0
        let previous = max(index - 1, 0)
        setStep(WingProtocol.selectableSteps[previous])
    }

    func oneKey(_ up: Bool) {
        commit(.oneKey(up: up)) { self.state.step = up ? 5 : 0 }
    }

    func setTrackType(_ type: Int) {
        commit(.track(type)) { self.state.trackType = type }
    }

    func toggleIgnition() {
        guard state.ignitionReady else {
            alertItem = .info("点火升降需在车内安装实体按键后才可使用")
            return
        }
        let desired = !state.ignitionOn
        pendingIgnitionDesired = desired
        commit(.ignition(desired))
    }

    // MARK: - 设备状态回复

    func handleReply(_ data: Data) {
        guard let telemetry = WingProtocol.parse(data) else { return }
        appendLog("收到状态 ← \(WingProtocol.hexString(data))")

        let previousStep = state.step
        state.speed = telemetry.speed
        state.isDescending = !(telemetry.step > previousStep)

        if state.isFirstReception {
            state.isFirstReception = false
            state.isAuto = (telemetry.autoFlag == 2)
            applySpeedIndices(down: telemetry.downSpeed, up: telemetry.upSpeed)
        }
        if state.isAuto {
            state.step = WingProtocol.selectableSteps.last(where: { $0 <= telemetry.step }) ?? 0
        }
        if let track = telemetry.trackType, (1...3).contains(track) {
            state.trackType = track
        }
        if let on = telemetry.ignitionOn { state.ignitionOn = on }
        if let ready = telemetry.ignitionReady { state.ignitionReady = ready }

        // 点火操作：等待设备回复后比对期望状态，成功进结果页，失败提示装按键
        if let desired = pendingIgnitionDesired {
            pendingIgnitionDesired = nil
            let actual = telemetry.ignitionOn ?? false
            if desired == actual {
                Haptics.success()
                sheet = .ignitionSuccess
            } else {
                Haptics.warning()
                sheet = .ignitionFailure
            }
        }
    }

    private func applySpeedIndices(down: Int, up: Int) {
        if let index = WingProtocol.downSpeeds.firstIndex(of: down) { state.downIndex = index }
        if let index = WingProtocol.upSpeeds.firstIndex(of: up) { state.upIndex = index }
    }

    // MARK: - 演示模式

    func setDemoMode(_ enabled: Bool) {
        demoMode = enabled
        if enabled {
            state.isFirstReception = true
            state.ignitionReady = demoHardwareButtonInstalled
            appendLog("已开启演示模式（无需真实硬件）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                self.handleReply(self.demoTelemetryData())
            }
        } else {
            appendLog("已关闭演示模式，请连接真实设备")
        }
    }

    func setDemoHardwareButton(_ installed: Bool) {
        demoHardwareButtonInstalled = installed
        if demoMode {
            state.ignitionReady = installed
            appendLog(installed ? "模拟：已安装车内实体按键" : "模拟：未安装车内实体按键")
        }
    }

    private func demoTelemetryData() -> Data {
        let bytes: [UInt8] = [
            0xBB, deviceID, 0x80,
            UInt8(state.isAuto ? 2 : 0),
            UInt8(state.step),
            UInt8(min(state.speed, 255)),
            UInt8(state.downSpeed),
            UInt8(state.upSpeed),
            UInt8(state.trackType),
            state.ignitionOn ? 1 : 0,
            state.ignitionReady ? 1 : 0,
            0x00
        ]
        return Data(bytes)
    }

    private func simulateReply(for command: WingCommand) {
        if case .ignition(let on) = command, demoHardwareButtonInstalled {
            state.ignitionOn = on
        }
        handleReply(demoTelemetryData())
    }

    // MARK: - 蓝牙操作包装

    func startScan() {
        appendLog("搜索设备：仅显示名称以 JDY 开头的控制器")
        ble.startScan()
    }

    func stopScan() { ble.stopScan() }

    func connect(_ device: BLEDevice) {
        appendLog("选择设备：\(device.name)")
        ble.connect(id: device.id)
    }

    func connectCached() {
        appendLog("连接上次使用的设备")
        ble.connectCached()
    }

    func disconnect() {
        state.isFirstReception = true
        ble.disconnect()
        appendLog("已断开连接")
    }
}
