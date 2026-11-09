import Foundation
import CoreBluetooth

// MARK: - 数据模型

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// 一个可写特征值的「写入通道」描述。
/// 原小程序只挑「同时支持 write + notify」的那一个特征值；
/// 真机上若选错通道，ATT 写入会成功但设备收不到命令，
/// 因此测试程序需要把设备暴露的每个可写通道逐个试一遍。
struct BLEWriteTarget: Identifiable, Equatable {
    let uuid: String
    let supportsWrite: Bool
    let supportsWriteWithoutResponse: Bool
    let supportsNotify: Bool

    var id: String { uuid }

    var shortName: String {
        let upper = uuid.uppercased()
        if upper.hasPrefix("FFE") { return upper }
        if upper.count > 8 { return String(upper.prefix(8)) }
        return upper
    }

    var propertyText: String {
        var tags: [String] = []
        if supportsWrite { tags.append("write") }
        if supportsWriteWithoutResponse { tags.append("writeNR") }
        if supportsNotify { tags.append("notify") }
        return tags.isEmpty ? "—" : tags.joined(separator: "+")
    }
}

enum BLEConnectionPhase: Equatable {
    case idle
    case scanning
    case connecting
    case discovering
    case ready
    case disconnected
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:            return "未连接"
        case .scanning:        return "正在扫描…"
        case .connecting:      return "连接中…"
        case .discovering:     return "正在读取服务…"
        case .ready:           return "已连接"
        case .disconnected:    return "已断开"
        case .failed(let msg): return msg
        }
    }
}

// MARK: - CoreBluetooth 封装

/// 对应原小程序的 openBluetoothAdapter / startBluetoothDevicesDiscovery /
/// createBLEConnection / getBLEDeviceServices / getBLEDeviceCharacteristics /
/// notifyBLECharacteristicValueChange / writeBLECharacteristicValue
final class BLEManager: NSObject, ObservableObject {

    @Published private(set) var phase: BLEConnectionPhase = .idle
    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var powerState: CBManagerState = .unknown
    @Published private(set) var authorization: CBManagerAuthorization = .notDetermined
    @Published private(set) var connectedName: String?
    @Published private(set) var characteristicInfo: String = "—"
    @Published private(set) var isUnsupported: Bool = false
    /// 全部可写特征值，供「一键协议测试」逐个切换写入通道
    @Published private(set) var writeTargets: [BLEWriteTarget] = []
    /// 所有主服务下的特征值清单（UUID + 属性），便于截图排查
    @Published private(set) var allCharacteristicInfo: String = "—"
    /// 写入回执：`.withoutResponse` 没有 ATT 回执，只有 `.withResponse` 会在
    /// `didWriteValueFor` 返回成功或失败。把结果暴露到界面，才能区分
    /// 「指令根本没送达蓝牙层」与「设备收到了但不执行」。
    @Published private(set) var lastWriteStatus: String = "—"
    @Published private(set) var writeAttemptCount = 0
    @Published private(set) var writeAckCount = 0
    @Published private(set) var writeFailureCount = 0
    /// 当前协商出的单次写入长度上限，排查「帧太长被截断」
    @Published private(set) var writeLengthInfo: String = "—"

    /// 收到 notify 数据、断开连接、日志文本的回调（均由主线程触发）
    var onData: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onLog: ((String) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    /// 所有已发现的特征值（可能来自多个主服务），测试矩阵按 UUID 从这里取写入目标
    private var discoveredCharacteristics: [CBCharacteristic] = []
    private var subscribedNotifyUUID: String?
    private var scanTimer: Timer?
    private var connectTimer: Timer?

    /// CBCentralManager 刚创建时 state 可能是 .unknown，需要等 poweredOn 后再执行用户操作
    private enum PendingAction {
        case scan
        case connect(UUID)
    }
    private var pendingAction: PendingAction?

    private static let lastIDKey = "wing.lastPeripheral"

    var cachedDeviceID: UUID? {
        UserDefaults.standard.string(forKey: Self.lastIDKey).flatMap { UUID(uuidString: $0) }
    }

    private func saveLastID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.lastIDKey)
    }

    /// 延迟创建 CBCentralManager：蓝牙权限只在用户主动「搜索/连接」时申请，不在启动时弹出
    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    private var unavailableMessage: String {
        switch powerState {
        case .poweredOff:   return "蓝牙开关未开启，请先在系统设置中打开蓝牙"
        case .unauthorized: return "蓝牙权限未开启，请在「设置 → 隐私与安全性 → 蓝牙」中允许"
        case .unsupported:  return "当前设备不支持蓝牙低功耗（iOS 模拟器请开启演示模式）"
        case .resetting:    return "蓝牙正在重置，请稍后重试"
        default:            return "本机蓝牙暂不可用，请稍后重试"
        }
    }

    // MARK: 对外操作

    func startScan() {
        ensureCentral()
        authorization = CBManager.authorization
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            performScan()
        case .unknown, .resetting:
            // 适配器尚未就绪，等 centralManagerDidUpdateState 回调后自动继续
            pendingAction = .scan
            phase = .scanning
            onLog?("等待本机蓝牙适配器就绪…")
        default:
            phase = .failed(unavailableMessage)
            onLog?(unavailableMessage)
        }
    }

    private func performScan() {
        guard let central else { return }
        devices.removeAll()
        peripherals.removeAll()
        phase = .scanning
        onLog?("开始扫描附近的蓝牙外围设备")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }

    func stopScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        central?.stopScan()
        if case .scanning = phase { phase = .idle }
        onLog?("停止搜寻附近的蓝牙外围设备")
    }

    func connect(id: UUID) {
        ensureCentral()
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            performConnect(id: id)
        case .unknown, .resetting:
            pendingAction = .connect(id)
            phase = .connecting
            onLog?("等待本机蓝牙适配器就绪…")
        default:
            phase = .failed(unavailableMessage)
        }
    }

    private func performConnect(id: UUID) {
        guard let central else { return }
        guard let target = peripherals[id]
                ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            phase = .failed("找不到该设备，请重新搜索")
            return
        }
        scanTimer?.invalidate()
        central.stopScan()
        phase = .connecting
        peripheral?.delegate = nil
        peripheral = target
        target.delegate = self
        saveLastID(id)
        connectedName = target.name ?? "JDY 尾翼控制器"
        onLog?("正在连接 \(connectedName ?? "设备")")
        central.connect(target, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self = self, case .connecting = self.phase else { return }
            self.central?.cancelPeripheralConnection(target)
            self.phase = .failed("连接超时，请重试")
            self.onLog?("连接超时，请重试")
        }
    }

    func connectCached() {
        guard let id = cachedDeviceID else { return }
        connect(id: id)
    }

    func disconnect() {
        pendingAction = nil
        scanTimer?.invalidate()
        connectTimer?.invalidate()
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        reset()
    }

    private func reset() {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        discoveredCharacteristics.removeAll()
        subscribedNotifyUUID = nil
        writeTargets = []
        allCharacteristicInfo = "—"
        peripheral?.delegate = nil
        peripheral = nil
        connectedName = nil
        characteristicInfo = "—"
        phase = .idle
    }

    /// 挑选写入 / 通知特征值：与原小程序一致，优先「同一个特征值同时可写可通知」。
    /// 找不到时才退化为分别挑选，此时极易选错，测试矩阵会遍历其余通道。
    private func refreshCharacteristics() {
        let all = discoveredCharacteristics
        let writable: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }
        let notifiable: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.uuid.uuidString.uppercased()).inserted }
        writeTargets = unique.filter(writable).map { item in
            BLEWriteTarget(
                uuid: item.uuid.uuidString,
                supportsWrite: item.properties.contains(.write),
                supportsWriteWithoutResponse: item.properties.contains(.writeWithoutResponse),
                supportsNotify: notifiable(item)
            )
        }
        allCharacteristicInfo = unique.map { item in
            "\(item.uuid.uuidString) [\(propertyList(of: item.properties))]"
        }.joined(separator: " | ")
        onLog?("特征值清单：\(allCharacteristicInfo)")

        if let combined = unique.first(where: { writable($0) && notifiable($0) }) {
            writeCharacteristic = combined
            notifyCharacteristic = combined
        } else {
            writeCharacteristic = unique.first(where: writable)
            notifyCharacteristic = unique.first(where: notifiable)
        }
        guard let write = writeCharacteristic, let notify = notifyCharacteristic else { return }
        characteristicInfo =
            "Service list · Write \(write.uuid.uuidString) · Notify \(notify.uuid.uuidString)"
        onLog?("当前通道：写 \(write.uuid.uuidString) / 通知 \(notify.uuid.uuidString)")
    }

    private func propertyList(of properties: CBCharacteristicProperties) -> String {
        var tags: [String] = []
        if properties.contains(.read) { tags.append("read") }
        if properties.contains(.write) { tags.append("write") }
        if properties.contains(.writeWithoutResponse) { tags.append("writeNR") }
        if properties.contains(.notify) { tags.append("notify") }
        if properties.contains(.indicate) { tags.append("indicate") }
        return tags.isEmpty ? "none" : tags.joined(separator: "+")
    }

    /// 按 UUID 指定写入目标；nil 表示用 refreshCharacteristics 选出的默认通道。
    private func characteristic(forUUID uuid: String?) -> CBCharacteristic? {
        guard let uuid else { return writeCharacteristic }
        let wanted = uuid.uppercased()
        return discoveredCharacteristics.first {
            $0.uuid.uuidString.uppercased() == wanted
        }
    }

    /// 微信小程序在 iOS 上对同时支持两种写的特征值走「无响应写」；
    /// 部分 JDY 模块固件也只按无响应写透传。这里做成可切换，并回退到特征值实际支持的模式。
    func write(_ data: Data, withoutResponse: Bool = true, targetUUID: String? = nil) {
        writeAttemptCount += 1
        guard let peripheral = peripheral,
              let characteristic = characteristic(forUUID: targetUUID),
              peripheral.state == .connected else {
            let targetName = targetUUID ?? "默认"
            let message = "失败：设备未连接或特征值不可用（目标 \(targetName)）"
            lastWriteStatus = message
            writeFailureCount += 1
            onLog?("发送命令失败：设备未连接或特征值不可用（目标 \(targetName)）")
            return
        }
        let supportsFast = characteristic.properties.contains(.writeWithoutResponse)
        let supportsAck = characteristic.properties.contains(.write)
        let type: CBCharacteristicWriteType
        if withoutResponse && supportsFast {
            type = .withoutResponse
        } else if supportsAck {
            type = .withResponse
        } else if supportsFast {
            type = .withoutResponse
        } else {
            let message = "失败：特征值 \(characteristic.uuid.uuidString) 不支持写入"
            lastWriteStatus = message
            writeFailureCount += 1
            onLog?(message)
            return
        }

        peripheral.writeValue(data, for: characteristic, type: type)
        let mode = type == .withResponse ? "带响应写" : "无响应写"
        let channel = targetUUID == nil ? "默认" : "指定"
        let short = String(characteristic.uuid.uuidString.prefix(8))
        if type == .withoutResponse {
            lastWriteStatus = "已提交 · \(short) · \(channel) · 无响应写（无 ATT 回执，无法确认设备是否收到）"
        } else {
            lastWriteStatus = "已提交 · \(short) · \(channel) · 带响应写 · 等待 ATT 回执"
        }
        onLog?("写入特征值 \(characteristic.uuid.uuidString) · \(channel) · \(mode) · \(WingProtocol.hexString(data))")
        // 无响应写不会触发 didWriteValueFor，日志里需要显式说明，避免被误判为「没发出去」
        if type == .withoutResponse {
            onLog?("命令已写入（无响应写，设备不返回 ATT 回执）")
        }
    }

    /// 对所有可写特征值各发一次：设备若有多个透传通道，总有一个能送达。
    func writeToAll(_ data: Data, withoutResponse: Bool) {
        let targets = writeTargets
        if targets.isEmpty {
            write(data, withoutResponse: withoutResponse)
            return
        }
        onLog?("群发：向 \(targets.count) 个可写特征值各写一次")
        for target in targets {
            write(data, withoutResponse: withoutResponse, targetUUID: target.uuid)
        }
    }

    /// 重新订阅 notify：部分 JDY 固件要求订阅动作发生在命令之前。
    func resubscribeNotify() {
        guard let peripheral = peripheral,
              let notify = notifyCharacteristic,
              peripheral.state == .connected else {
            onLog?("重新订阅失败：通知特征值不可用")
            return
        }
        onLog?("重新订阅 notify：\(notify.uuid.uuidString)")
        peripheral.setNotifyValue(false, for: notify)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            self.peripheral?.setNotifyValue(true, for: notify)
        }
    }

    /// 读取全部可读特征值：部分 JDY 固件要求先 read 才允许写，或需要 read 触发
    /// 系统配对。失败时 `didUpdateValueFor` 会给出 insufficientEncryption /
    /// insufficientAuthentication 之类错误码，能直接定位「写入被设备拒绝」。
    func readAllReadableCharacteristics() {
        guard let peripheral = peripheral, peripheral.state == .connected else {
            onLog?("读取失败：蓝牙未连接")
            return
        }
        let readable = discoveredCharacteristics.filter { $0.properties.contains(.read) }
        guard !readable.isEmpty else {
            onLog?("该设备没有可读特征值（不影响写入测试）")
            return
        }
        onLog?("读取 \(readable.count) 个可读特征值，用于触发配对 / 固件握手")
        for item in readable {
            peripheral.readValue(for: item)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        powerState = central.state
        authorization = CBManager.authorization
        isUnsupported = (central.state == .unsupported)
        switch central.state {
        case .poweredOn:
            onLog?("本机蓝牙适配器状态：可用")
            if let pendingAction {
                self.pendingAction = nil
                switch pendingAction {
                case .scan:          performScan()
                case .connect(let id): performConnect(id: id)
                }
            } else if case .failed = phase {
                phase = .idle
            }
        case .poweredOff, .unauthorized, .unsupported:
            pendingAction = nil
            phase = .failed(unavailableMessage)
            onLog?(unavailableMessage)
            // 蓝牙开关关闭 / 权限被收回同样要让测试立刻停机，不能只靠下一步轮询
            onDisconnect?()
        case .resetting:
            onLog?("蓝牙正在重置，请稍后重试")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised ?? ""
        // 与原小程序一致：仅接受名称以 "JDY" 开头的蓝牙模块
        guard name.uppercased().hasPrefix("JDY") else { return }

        peripherals[peripheral.identifier] = peripheral
        let device = BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimer?.invalidate()
        phase = .discovering
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        onLog?("连接成功：\(peripheral.name ?? "JDY")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectTimer?.invalidate()
        phase = .failed("连接失败，请重试")
        onLog?("连接失败：\(error?.localizedDescription ?? "未知错误")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        reset()
        phase = .disconnected
        onLog?("蓝牙已断开")
        onDisconnect?()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            phase = .failed("获取服务失败：\(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            phase = .failed("该设备没有可用服务")
            return
        }
        // 原小程序只扫描第一个 isPrimary 服务；CoreBluetooth 返回顺序不保证一致，
        // 这里把所有主服务都扫一遍，避免漏掉真正的透传服务（FFE0/FFE1）。
        let primaries = services.filter { $0.isPrimary }
        let targets = primaries.isEmpty ? services : primaries
        discoveredCharacteristics.removeAll()
        subscribedNotifyUUID = nil
        onLog?("发现服务 \(services.count) 个，扫描主服务 \(targets.count) 个")
        for service in targets {
            onLog?("主服务：\(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            phase = .failed("获取特征值失败：\(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics, !characteristics.isEmpty else {
            return
        }
        discoveredCharacteristics.append(contentsOf: characteristics)
        refreshCharacteristics()

        guard let write = writeCharacteristic, let notify = notifyCharacteristic else {
            phase = .failed("未找到可写 / 可通知的特征值")
            return
        }
        characteristicInfo =
            "Write \(write.uuid.uuidString) · Notify \(notify.uuid.uuidString) · 可写通道 \(writeTargets.count) 个"
        // 后续服务里若出现更合适的通知特征值，改订阅到新的那个
        let key = notify.uuid.uuidString.uppercased()
        if subscribedNotifyUUID != key {
            subscribedNotifyUUID = key
            peripheral.setNotifyValue(true, for: notify)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            phase = .failed("订阅通知失败：\(error.localizedDescription)")
            return
        }
        guard characteristic.isNotifying else { return }
        phase = .ready
        let ackLength = peripheral.maximumWriteValueLength(for: .withResponse)
        let nrLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        writeLengthInfo = "带响应 \(ackLength) 字节 / 无响应 \(nrLength) 字节"
        onLog?("notify 启动成功，特征值 \(characteristic.uuid.uuidString)")
        onLog?("单次写入长度上限：\(writeLengthInfo)")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            let code = (error as NSError).code
            onLog?("特征值读取 / 通知失败：\(characteristic.uuid.uuidString) · code=\(code) · \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value, !value.isEmpty else { return }
        if characteristic.isNotifying {
            onData?(value)
        } else {
            onLog?("读取特征值 \(characteristic.uuid.uuidString) ← \(WingProtocol.hexString(value))")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let short = String(characteristic.uuid.uuidString.prefix(8))
        if let error = error {
            let code = (error as NSError).code
            let message = "ATT 写入失败 · \(short) · code=\(code) · \(error.localizedDescription)"
            lastWriteStatus = message
            writeFailureCount += 1
            onLog?(message)
        } else {
            let message = "ATT 写入成功 · \(short) · 设备已确认"
            lastWriteStatus = message
            writeAckCount += 1
            onLog?(message)
        }
    }
}
