import Foundation
import Combine
import UIKit

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

    // MARK: - 指令 ID 与写入方式（真机联调）

    /// 当前命令帧第 2 字节，十六进制大写
    @Published private(set) var deviceIDHex: String = "00"
    /// 设备状态帧回传的第 2 字节
    @Published private(set) var learnedDeviceIDHex: String?
    /// 上一条发出的完整帧，供「重发」使用
    @Published private(set) var lastCommandHex: String = ""
    /// true = 无响应写（与微信小程序一致）；false = 带响应写
    @Published private(set) var useWriteWithoutResponse: Bool = true
    /// 收到状态帧时是否自动校正 did；排查时可关闭，以便手动指定值做对比
    @Published private(set) var autoSyncDeviceID: Bool = true

    /// 一条便于用户直接点发送的测试帧：把档位设为 3
    var suggestedTestFrame: String { "BB\(deviceIDHex)80010300" }

    let ble = BLEManager()

    private let defaults = UserDefaults.standard
    private let deviceIDKey = "wing.deviceID"
    private let launchLogKey = "wing.launchLogs"
    private var deviceID: UInt8 = 0
    private var deviceIDSource: String = "首次随机"
    private var pendingIgnitionDesired: Bool?
    private var pendingCalibrationIndices: (Int, Int)?
    private var cancellable: AnyCancellable?

    // 指令响应检测：设备每秒上报状态帧，命令生效后帧内容必然改变
    @Published private(set) var lastTelemetryHex: String?
    /// 每解析一帧状态就自增，供测试程序判断是否真的收到了新帧
    @Published private(set) var telemetryRevision = 0
    private var baselineTelemetryHex: String?
    private var awaitingReply = false
    private var replyCheckWorkItem: DispatchWorkItem?

    /// 一键协议测试运行器（用例矩阵 / 定时推进 / 结果报告）
    let testRunner = WingTestRunner()

    init() {
        // 与原小程序一致：首次生成随机 did(0~255) 并缓存。
        // 真机日志表明设备只认可它记住的 did，连接后会由状态帧自动同步覆盖。
        if let saved = defaults.object(forKey: deviceIDKey) as? Int {
            deviceID = UInt8(saved & 0xFF)
            deviceIDSource = "本机缓存"
        } else {
            deviceID = UInt8.random(in: UInt8.min ... UInt8.max)
            deviceIDSource = "首次随机"
            defaults.set(Int(deviceID), forKey: deviceIDKey)
        }
        deviceIDHex = String(format: "%02X", deviceID)
        testRunner.attach(self)

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
            self.learnedDeviceIDHex = nil
            self.lastTelemetryHex = nil
            self.replyCheckWorkItem?.cancel()
            self.awaitingReply = false
            self.appendLog("设备断开，等待重新连接")
            // 测试运行器必须同步停机：否则编号继续推进、排队中的写入还会照发
            self.testRunner.handleDisconnect()
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
        appendLog("App 启动 · did=\(deviceIDHex) · 来源=\(deviceIDSource)")
    }

    func appendLog(_ text: String) {
        logs.insert(LogEntry(date: Date(), text: text), at: 0)
        if logs.count > 200 { logs = Array(logs.prefix(200)) }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - 指令 ID / 写入方式

    /// 更新 did 并持久化。所有命令帧都从这里取值，避免再用首次随机值与设备错配。
    private func applyDeviceID(_ value: UInt8, source: String) {
        let old = deviceIDHex
        deviceID = value
        deviceIDHex = String(format: "%02X", value)
        deviceIDSource = source
        defaults.set(Int(value), forKey: deviceIDKey)
        appendLog("指令 ID：\(old) → \(deviceIDHex)（\(source)）")
    }

    /// 「设备 → 协议诊断」里手动指定 did，例如真机日志里的 1C
    func setDeviceID(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .uppercased()
        guard cleaned.count == 2, let value = UInt8(cleaned, radix: 16) else {
            alertItem = .info("指令 ID 需要 2 位十六进制，例如 1C")
            return
        }
        applyDeviceID(value, source: "手动指定")
    }

    func setWriteMode(withoutResponse: Bool) {
        useWriteWithoutResponse = withoutResponse
        appendLog("写入方式：\(withoutResponse ? "无响应写（与微信小程序一致）" : "带响应写")")
    }

    func setAutoSyncDeviceID(_ enabled: Bool) {
        autoSyncDeviceID = enabled
        appendLog("did 自动同步：\(enabled ? "开启" : "关闭（可手动指定 did 做对比）")")
    }

    /// 直接发送用户输入的原始帧，用于逐个验证 did / 写入方式
    func sendRawFrame(hex: String) {
        guard let data = WingProtocol.data(fromHex: hex) else {
            alertItem = .info("请输入偶数位十六进制，例如 BB1C80010300")
            return
        }
        guard !demoMode else {
            alertItem = .info("演示模式下不发送真实蓝牙帧，请先关闭演示模式")
            return
        }
        guard isConnected else {
            alertItem = .info("设备未连接，请先到「设备」页连接控制器")
            return
        }
        lastCommandHex = WingProtocol.hexString(data)
        appendLog("发送测试帧 → \(lastCommandHex)")
        ble.write(data, withoutResponse: useWriteWithoutResponse)
        armReplyCheck()
    }

    func resendLastFrame() {
        guard !lastCommandHex.isEmpty else {
            alertItem = .info("还没有发送过指令")
            return
        }
        sendRawFrame(hex: lastCommandHex)
    }

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
        lastCommandHex = WingProtocol.hexString(frame)
        appendLog("发送 \(command.displayName) → \(lastCommandHex) [did=\(deviceIDHex)]")

        if demoMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.simulateReply(for: command)
            }
        } else {
            ble.write(frame, withoutResponse: useWriteWithoutResponse)
            armReplyCheck()
        }
    }

    /// 设备每秒上报一次状态帧。若 3.5 秒内帧内容完全没变，说明命令被忽略了。
    private func armReplyCheck() {
        replyCheckWorkItem?.cancel()
        awaitingReply = true
        baselineTelemetryHex = lastTelemetryHex
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.awaitingReply else { return }
            self.awaitingReply = false
            self.appendLog(
                "注意：指令发出后状态帧没有变化，设备可能忽略了这条命令。"
                + "请到「设备 → 协议诊断」核对指令 ID，或切换写入方式后重发。"
            )
        }
        replyCheckWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
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
        let hex = WingProtocol.hexString(data)
        guard let telemetry = WingProtocol.parse(data) else {
            appendLog("收到无法解析的数据 ← \(hex)")
            return
        }
        appendLog("收到状态 ← \(hex)")
        telemetryRevision += 1

        // 命令生效后状态帧必然变化；用于判断设备是「收到」还是「执行」。
        // 若发命令前还没收到过任何状态帧，则这一帧本身就算设备有回应。
        if awaitingReply {
            let changed = baselineTelemetryHex.map { $0 != hex } ?? true
            if changed {
                awaitingReply = false
                replyCheckWorkItem?.cancel()
                appendLog("设备已响应：状态帧发生变化")
            }
        }
        lastTelemetryHex = hex

        // 核心修复：设备状态帧第 2 字节是它认可的 did。
        // App 首次启动随机生成的 did 与设备记住的（原微信小程序）不同时，
        // 设备会静默忽略所有命令，但 CoreBluetooth 的写入回调依然成功。
        let learned = String(format: "%02X", telemetry.deviceID)
        learnedDeviceIDHex = learned
        if autoSyncDeviceID && telemetry.deviceID != deviceID {
            applyDeviceID(telemetry.deviceID, source: "按设备状态帧同步")
        }

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

    // MARK: - 一键协议测试（用例矩阵与底层发送）

    /// 报告开头记录当时的连接 / did / 特征值环境，便于对照截图
    func testEnvironmentText() -> String {
        let learned = learnedDeviceIDHex ?? "—"
        return "连接=\(connectionText) | did=\(deviceIDHex) | 设备回传=\(learned) | 特征值=\(ble.allCharacteristicInfo) | 可写通道=\(ble.writeTargets.count) | 写入长度=\(ble.writeLengthInfo)"
    }

    func resubscribeNotifyForTest() { ble.resubscribeNotify() }

    /// 测试运行期间排队的写入任务，停止测试时一并取消，避免关闭面板后还继续发指令
    private var testSendTasks: [DispatchWorkItem] = []

    func cancelTestWrites() {
        for task in testSendTasks { task.cancel() }
        testSendTasks.removeAll()
    }

    /// 测试专用发送：不触发常规指令的 3.5 秒诊断，避免刷屏；
    /// 所有帧在开始测试时就已生成快照，运行过程中 did 自动同步不会影响编号含义。
    func sendTestFrames(
        _ frames: [Data],
        withoutResponse: Bool,
        targetUUID: String?,
        broadcast: Bool,
        note: String
    ) {
        cancelTestWrites()
        guard !demoMode else {
            appendLog("测试中止：演示模式未关闭，指令不会发到蓝牙")
            return
        }
        guard isConnected else {
            appendLog("测试中止：设备未连接")
            return
        }
        if let first = frames.first { lastCommandHex = WingProtocol.hexString(first) }
        let hexList = frames.map { WingProtocol.hexString($0) }.joined(separator: " / ")
        appendLog("\(note) → \(hexList)")
        for (index, item) in frames.enumerated() {
            let delay = Double(index) * 0.16
            let task = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard self.isConnected else {
                    self.appendLog("测试指令未发送：蓝牙已断开")
                    self.testRunner.handleDisconnect()
                    return
                }
                if broadcast {
                    self.ble.writeToAll(item, withoutResponse: withoutResponse)
                } else {
                    self.ble.write(item, withoutResponse: withoutResponse, targetUUID: targetUUID)
                }
            }
            testSendTasks.append(task)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        }
    }

    /// 严格复刻小程序的单次发送：默认通道（小程序只认同时支持 write + notify 的
    /// 那个特征值）、带响应写、did 用设备状态帧回传值、命令为「一键上升」。
    /// 与穷举矩阵做对照：连这一帧都不动，问题就在连接 / 配对层，而不是帧内容。
    func sendOriginalProbe() {
        cancelTestWrites()
        guard !demoMode else {
            appendLog("原样复刻中止：请先关闭演示模式")
            return
        }
        guard isConnected else {
            appendLog("原样复刻中止：蓝牙未连接")
            testRunner.handleDisconnect()
            return
        }
        let did = learnedDeviceIDHex ?? deviceIDHex
        let hex = "BB\(did)80060100"
        let data = WingProtocol.data(fromHex: hex) ?? Data()
        lastCommandHex = hex
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.isConnected else {
                self.appendLog("原样复刻未发送：蓝牙已断开")
                self.testRunner.handleDisconnect()
                return
            }
            self.ble.write(data, withoutResponse: false, targetUUID: nil)
        }
        testSendTasks.append(work)
        DispatchQueue.main.async(execute: work)
        appendLog("原样复刻小程序：带响应写 / 默认通道 / \(hex)")
    }

    /// 生成测试矩阵。每一项都有稳定编号，用户只需记下「尾翼动了」的编号。
    /// 变量：写入通道、写入方式、帧内容与长度、指令 ID、发送时序。
    func buildTestCases(mode: WingTestMode) -> [WingTestCase] {
        let did = deviceIDHex
        let learned = learnedDeviceIDHex ?? did
        let targets = ble.writeTargets
        var list: [WingTestCase] = []

        func frame(_ hex: String) -> Data { WingProtocol.data(fromHex: hex) ?? Data() }
        func add(
            _ title: String,
            _ detail: String,
            _ frames: [Data],
            // 默认带响应写：只有它才有 ATT 回执，能看出「没送达」还是「设备不执行」
            nr: Bool = false,
            target: String? = nil,
            broadcast: Bool = false,
            resubscribe: Bool = false,
            lead: TimeInterval = 0,
            hold: TimeInterval = 1.8
        ) {
            let hexList = frames.map { WingProtocol.hexString($0) }.joined(separator: " / ")
            list.append(WingTestCase(
                id: list.count + 1,
                title: title,
                detail: detail,
                frames: frames,
                frameHex: hexList,
                withoutResponse: nr,
                targetUUID: target,
                broadcast: broadcast,
                resubscribe: resubscribe,
                leadDelay: lead,
                hold: hold
            ))
        }

        if mode == .standard {
            let standardHex = "BB\(did)80010500"
            let standard = frame(standardHex)
            let bytes = [UInt8](standard)

            // A. 每个可写通道 × 两种写入方式：排除「写错特征值」这个最隐蔽的原因
            let channels: [String?] = targets.isEmpty ? [nil] : targets.map { Optional($0.uuid) }
            for uuid in channels {
                let name = uuid.map { wingShortUUID($0) } ?? "默认通道"
                add("通道 \(name) · 无响应写", "标准帧 / 无响应写 / \(name)",
                    [standard], nr: true, target: uuid)
                add("通道 \(name) · 带响应写", "标准帧 / 带响应写 / \(name)",
                    [standard], nr: false, target: uuid)
            }

            // B. 原小程序所有命令字，以及帧长 / 校验 / ASCII / 时序等常见变体
            let variants: [(String, String)] = [
                ("标准 6 字节 · 档位 5", standardHex),
                ("一键上升", "BB\(did)80060100"),
                ("一键下降", "BB\(did)80060200"),
                ("设置档位 3", "BB\(did)80010300"),
                ("关闭自动升降", "BB\(did)80030000"),
                ("开启自动升降 10/80", "BB\(did)80020A50"),
                ("赛道灵敏度 1", "BB\(did)80040100"),
                ("点火升降开", "BB\(did)80050100"),
                ("唤醒帧 8000", "BB\(did)80000000"),
                ("第 3 字节改 20", "BB\(did)20010500"),
                ("帧头改 AA", "AA\(did)80010500"),
                ("去掉 did 的 5 字节", "BB80010500")
            ]
            for variant in variants {
                add(variant.0, "帧变体 / 默认通道 / 无响应写", [frame(variant.1)])
            }

            let sum = UInt8(bytes.reduce(0) { $0 + Int($1) } % 256)
            let xor = bytes.reduce(UInt8(0)) { $0 ^ $1 }
            add("ASCII 大写 12 字节", "把整帧当字符串写入", [Data(standardHex.uppercased().utf8)])
            add("ASCII 小写 12 字节", "把整帧当字符串写入", [Data(standardHex.lowercased().utf8)])
            add("6 字节 + 回车换行", "帧尾 CRLF", [Data(bytes + [0x0D, 0x0A])])
            add("6 字节 + 累加校验", "第 7 字节为累加和", [Data(bytes + [sum])])
            add("6 字节 + 异或校验", "第 7 字节为异或值", [Data(bytes + [xor])])
            add("补零到 12 字节", "部分固件按固定长度收帧", [Data(bytes + [UInt8](repeating: 0, count: 6))])
            add("补零到 20 字节", "按 BLE MTU 固定长度收帧", [Data(bytes + [UInt8](repeating: 0, count: 14))])
            add("整帧字节反序", "字节序颠倒", [Data(bytes.reversed())])
            add("同一帧连发 3 次", "排除单次写入被丢弃", [standard, standard, standard])
            add("上升 + 下降交替", "让动作更容易被看见",
                [frame("BB\(did)80060100"), frame("BB\(did)80060200")])
            add("重新订阅 notify 后发", "先关再开通知", [standard], resubscribe: true)
            add("群发全部可写通道", "一次写遍所有特征值", [standard], broadcast: true)
            add("带响应写 · 延迟再发一次", "有回执 + 重复", [standard, standard], nr: false, hold: 2.6)
            add("等待 5 秒后再发", "小程序启动后有 5 秒延时", [standard], lead: 5, hold: 2.4)

            // C. 常见 did 候选（含状态帧第 2 字节、本机缓存值）
            var candidates = ["00", "01", "0A", "0B", "10", "1C", "20", "7F", "80", "FF", learned, did]
            var seen = Set<String>()
            candidates = candidates.filter { seen.insert($0).inserted }
            for candidate in candidates {
                add("did=\(candidate) · 标准帧", "指令 ID 候选 / 默认通道",
                    [frame("BB\(candidate)80010500")])
            }
        } else {
            // did 全扫描：0x00~0xFF 逐个试，一帧上升 + 一帧下降保证动作可见。
            // 若设备按 did 过滤命令，这一步一定能找出它认可的值。
            for value in 0...255 {
                let hex = String(format: "%02X", value)
                let up = frame("BB\(hex)80060100")
                let down = frame("BB\(hex)80060200")
                add("did 全扫描 \(hex)", "上升 + 下降 / did=\(hex)", [up, down], nr: true, hold: 0.7)
            }
        }
        return list
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

// MARK: - 一键协议测试：数据模型与运行器

private func wingShortUUID(_ uuid: String) -> String {
    let upper = uuid.uppercased()
    if upper.count > 8 { return String(upper.prefix(8)) }
    return upper
}

enum WingTestMode: String, CaseIterable, Identifiable {
    case standard = "标准矩阵"
    case didScan = "did 全扫描"

    var id: String { rawValue }
}

/// 一个待试的发送组合。编号在测试开始时一次性生成并固定，
/// 用户只要回报「#几 有效」即可精确定位原因。
struct WingTestCase: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let frames: [Data]
    let frameHex: String
    let withoutResponse: Bool
    let targetUUID: String?
    let broadcast: Bool
    let resubscribe: Bool
    let leadDelay: TimeInterval
    let hold: TimeInterval

    var channelText: String {
        let mode = withoutResponse ? "无响应写" : "带响应写"
        if broadcast { return "群发全部通道 · \(mode)" }
        let target = targetUUID.map { wingShortUUID($0) } ?? "默认通道"
        return "\(target) · \(mode)"
    }
}

struct WingTestResult: Identifiable {
    let id: Int
    let caseID: Int
    let title: String
    let frameHex: String
    let channel: String
    let telemetryChanged: Bool
    var userMarked: Bool
}

/// 逐项自动发送：每项停留 hold 秒供用户观察尾翼动作，
/// 同时记录状态帧是否变化作为辅助判定，最后生成可复制的文本报告。
final class WingTestRunner: ObservableObject {

    @Published private(set) var cases: [WingTestCase] = []
    @Published private(set) var results: [WingTestResult] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false
    @Published private(set) var mode: WingTestMode = .standard
    @Published private(set) var successIDs: [Int] = []
    @Published private(set) var statusText = "未开始"
    @Published private(set) var reportCopied = false
    @Published private(set) var environment = ""
    /// 非空表示测试被蓝牙断开中断，面板要显示醒目提示（文字 + 图标，不只靠颜色）
    @Published private(set) var interruptedReason: String?

    // 属性名刻意不与局部 `guard let controller` 同名，避免对非可选局部常量误用 `?.`
    private weak var owner: WingController?
    private var pending: DispatchWorkItem?
    private var baselineHex: String?
    private var baselineRevision = 0
    private var singleStepMode = false

    func attach(_ controller: WingController) { owner = controller }

    var currentCase: WingTestCase? {
        guard currentIndex > 0, currentIndex <= cases.count else { return nil }
        return cases[currentIndex - 1]
    }

    var progress: Double {
        guard !cases.isEmpty else { return 0 }
        return Double(currentIndex) / Double(cases.count)
    }

    // MARK: 运行控制

    /// 蓝牙断开：立刻取消排队的写入与编号推进，并把原因显示在面板与报告里。
    /// 小程序本身也用 onBLEConnectionStateChange 弹「蓝牙已断开」并停止操作。
    func handleDisconnect() {
        guard isRunning || singleStepMode || (!cases.isEmpty && !isFinished) else { return }
        pending?.cancel()
        owner?.cancelTestWrites()
        isRunning = false
        singleStepMode = false
        let at = currentIndex > 0 ? "第 #\(currentIndex) 项" : "开始时"
        let reason = "蓝牙已断开（\(at)），测试已停止，后续指令全部取消"
        interruptedReason = reason
        statusText = "⚠️ 蓝牙已断开，测试已停止"
        owner?.appendLog("⚠️ \(reason)")
    }

    /// 单项对照：严格按小程序发一次「一键上升」，用于确认问题是否在连接层。
    func probeOriginal() {
        guard let controller = owner, controller.isConnected else {
            statusText = "请先连接蓝牙，再试原样命令"
            owner?.appendLog("原样命令未发送：蓝牙未连接")
            return
        }
        owner?.cancelTestWrites()
        controller.sendOriginalProbe()
        statusText = "已发小程序原样命令（一键上升）"
    }

    func start(mode: WingTestMode) {
        guard let controller = owner else { return }
        guard !controller.demoMode else {
            statusText = "请先关闭演示模式"
            return
        }
        guard controller.isConnected else {
            statusText = "请先连接设备"
            return
        }
        pending?.cancel()
        owner?.cancelTestWrites()
        singleStepMode = false
        self.mode = mode
        cases = controller.buildTestCases(mode: mode)
        results = []
        currentIndex = 0
        successIDs = []
        isFinished = false
        reportCopied = false
        interruptedReason = nil
        environment = controller.testEnvironmentText()
        statusText = "准备开始 · 共 \(cases.count) 项"
        controller.appendLog("=== 一键协议测试开始：\(mode.rawValue) / 共 \(cases.count) 项 ===")
        isRunning = true
        runNext()
    }

    private func runNext() {
        guard isRunning || singleStepMode else { return }
        // 每一步都重新确认连接：蓝牙可能在等待期间掉线，不能继续往队列里塞写入
        guard let connected = owner?.isConnected, connected else {
            handleDisconnect()
            return
        }
        guard currentIndex < cases.count else {
            finish()
            return
        }
        currentIndex += 1
        let item = cases[currentIndex - 1]
        statusText = "正在执行 #\(item.id) / \(cases.count)"
        baselineHex = owner?.lastTelemetryHex
        baselineRevision = owner?.telemetryRevision ?? 0
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.execute(item)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + item.leadDelay, execute: work)
    }

    private func execute(_ item: WingTestCase) {
        guard let controller = owner else { return }
        guard controller.isConnected else {
            handleDisconnect()
            return
        }
        if item.resubscribe { controller.resubscribeNotifyForTest() }
        controller.sendTestFrames(
            item.frames,
            withoutResponse: item.withoutResponse,
            targetUUID: item.targetUUID,
            broadcast: item.broadcast,
            note: "测试 #\(item.id) \(item.title)"
        )
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.evaluate(item)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + item.hold, execute: work)
    }

    private func evaluate(_ item: WingTestCase) {
        guard let controller = owner else { return }
        var changed = false
        if controller.telemetryRevision > baselineRevision,
           let now = controller.lastTelemetryHex {
            changed = (now != baselineHex)
        }
        results.append(WingTestResult(
            id: results.count + 1,
            caseID: item.id,
            title: item.title,
            frameHex: item.frameHex,
            channel: item.channelText,
            telemetryChanged: changed,
            userMarked: false
        ))
        let verdict = changed ? "状态帧变化（可能生效）" : "状态帧未变化"
        controller.appendLog("测试 #\(item.id) 结果：\(verdict) · \(item.frameHex)")
        if isRunning && !singleStepMode {
            runNext()
        } else {
            singleStepMode = false
            statusText = "已暂停 · #\(item.id) 完成"
        }
    }

    func pause() {
        pending?.cancel()
        owner?.cancelTestWrites()
        isRunning = false
        singleStepMode = false
        statusText = "已暂停"
        owner?.appendLog("一键协议测试已暂停")
    }

    func resume() {
        guard !cases.isEmpty, !isFinished else { return }
        guard let connected = owner?.isConnected, connected else {
            statusText = "请先重新连接蓝牙，再点继续"
            return
        }
        // 暂停发生在等待中时，当前项还没有结果，重跑它
        if currentIndex > 0, !results.contains(where: { $0.caseID == currentIndex }) {
            currentIndex -= 1
        }
        isRunning = true
        singleStepMode = false
        statusText = "继续执行"
        runNext()
    }

    func stepForward() {
        pending?.cancel()
        owner?.cancelTestWrites()
        isRunning = false
        if cases.isEmpty {
            guard let controller = owner else { return }
            cases = controller.buildTestCases(mode: mode)
            environment = controller.testEnvironmentText()
        }
        guard currentIndex < cases.count else {
            statusText = "已经是最后一项"
            return
        }
        isFinished = false
        singleStepMode = true
        runNext()
    }

    func restartCurrent() {
        pending?.cancel()
        owner?.cancelTestWrites()
        isRunning = false
        guard currentIndex > 0 else {
            statusText = "尚未开始测试"
            return
        }
        currentIndex -= 1
        singleStepMode = true
        runNext()
    }

    func stop() {
        pending?.cancel()
        owner?.cancelTestWrites()
        isRunning = false
        singleStepMode = false
    }

    func reset() {
        stop()
        cases = []
        results = []
        currentIndex = 0
        successIDs = []
        isFinished = false
        reportCopied = false
        interruptedReason = nil
        statusText = "未开始"
    }

    // MARK: 结果记录

    /// 用户看到尾翼动了就点一下：把当前编号写进报告
    func markSuccess() {
        guard let item = currentCase else {
            statusText = "请先开始测试"
            return
        }
        if !successIDs.contains(item.id) { successIDs.append(item.id) }
        if let index = results.lastIndex(where: { $0.caseID == item.id }) {
            results[index].userMarked = true
        }
        owner?.appendLog("★ 用户标记：测试 #\(item.id) 有效 · \(item.frameHex)")
        statusText = "已标记 #\(item.id) 成功"
    }

    func reportText() -> String {
        var lines: [String] = []
        lines.append("尾翼控制器 · 一键协议测试报告")
        lines.append("模式：\(mode.rawValue)")
        lines.append("环境：\(environment)")
        lines.append("用例：\(cases.count) 项 / 已执行 \(results.count) 项")
        let marks = successIDs.sorted().map { "#\($0)" }.joined(separator: ", ")
        let markText = marks.isEmpty ? "无" : marks
        lines.append("★ 用户标记成功：\(markText)")
        let auto = results.filter { $0.telemetryChanged }
            .map { "#\($0.caseID)" }.joined(separator: ", ")
        let autoText = auto.isEmpty ? "无" : auto
        lines.append("状态帧有变化：\(autoText)")
        if let ble = owner?.ble {
            lines.append("写入统计：尝试 \(ble.writeAttemptCount) 次 / ATT 成功 \(ble.writeAckCount) 次 / 失败 \(ble.writeFailureCount) 次（无响应写没有 ATT 回执，不计入成功或失败）")
            lines.append("最后一次写入回执：\(ble.lastWriteStatus)")
            lines.append("写入长度上限：\(ble.writeLengthInfo)")
            lines.append("完整特征值清单：\(ble.allCharacteristicInfo)")
        }
        if let interrupted = interruptedReason {
            lines.append("⚠️ 中断：\(interrupted)")
        }
        lines.append("--- 明细：编号 | 说明 | 帧 | 通道 | 自动判定 | 用户标记 ---")
        var map: [Int: WingTestResult] = [:]
        for result in results { map[result.caseID] = result }
        for item in cases {
            let result = map[item.id]
            let judge: String
            if let value = result {
                judge = value.telemetryChanged ? "帧变化" : "帧未变"
            } else {
                judge = "未执行"
            }
            let marked = (result?.userMarked ?? false) ? "★成功" : ""
            lines.append("#\(item.id) | \(item.title) | \(item.frameHex) | \(item.channelText) | \(judge) | \(marked)")
        }
        return lines.joined(separator: "\n")
    }

    func copyReport() {
        UIPasteboard.general.string = reportText()
        reportCopied = true
        statusText = "报告已复制，可直接粘贴发送"
        owner?.appendLog("测试报告已复制到剪贴板")
    }

    private func finish() {
        pending?.cancel()
        isRunning = false
        singleStepMode = false
        isFinished = true
        statusText = "全部完成 · 共 \(cases.count) 项"
        owner?.appendLog("=== 一键协议测试结束：用户标记 \(successIDs.count) 项成功 ===")
    }
}
