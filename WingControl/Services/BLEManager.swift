import Foundation
import CoreBluetooth

// MARK: - 数据模型

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
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

    /// 收到 notify 数据、断开连接、日志文本的回调（均由主线程触发）
    var onData: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onLog: ((String) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
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
        peripheral?.delegate = nil
        peripheral = nil
        connectedName = nil
        characteristicInfo = "—"
        phase = .idle
    }

    /// 微信小程序在 iOS 上对同时支持两种写的特征值走「无响应写」；
    /// 部分 JDY 模块固件也只按无响应写透传。这里做成可切换，并回退到特征值实际支持的模式。
    func write(_ data: Data, withoutResponse: Bool = true) {
        guard let peripheral,
              let characteristic = writeCharacteristic,
              peripheral.state == .connected else {
            onLog?("发送命令失败：设备未连接或特征值不可用")
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
            onLog?("发送命令失败：特征值 \(characteristic.uuid.uuidString) 不支持写入")
            return
        }

        peripheral.writeValue(data, for: characteristic, type: type)
        let mode = type == .withResponse ? "带响应写" : "无响应写"
        onLog?("写入特征值 \(characteristic.uuid.uuidString) · \(mode) · \(WingProtocol.hexString(data))")
        // 无响应写不会触发 didWriteValueFor，日志里需要显式说明，避免被误判为「没发出去」
        if type == .withoutResponse {
            onLog?("命令已写入（无响应写，设备不返回 ATT 回执）")
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
        let primary = services.first(where: { $0.isPrimary }) ?? services[0]
        onLog?("主服务：\(primary.uuid.uuidString)")
        peripheral.discoverCharacteristics(nil, for: primary)
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
            phase = .failed("该服务没有可用特征值")
            return
        }
        let writable: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }
        let notifiable: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }

        // 优先选「同时支持 write + notify」的单特征值（JDY 模块常见 FFE1）
        if let combined = characteristics.first(where: { writable($0) && notifiable($0) }) {
            writeCharacteristic = combined
            notifyCharacteristic = combined
        } else {
            writeCharacteristic = characteristics.first(where: writable)
            notifyCharacteristic = characteristics.first(where: notifiable)
        }

        guard let write = writeCharacteristic, let notify = notifyCharacteristic else {
            phase = .failed("未找到可写 / 可通知的特征值")
            return
        }
        characteristicInfo =
            "Service \(service.uuid.uuidString) · Write \(write.uuid.uuidString) · Notify \(notify.uuid.uuidString)"
        onLog?(characteristicInfo)
        peripheral.setNotifyValue(true, for: notify)
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
        onLog?("notify 启动成功，特征值 \(characteristic.uuid.uuidString)")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value, !value.isEmpty else { return }
        onData?(value)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error { onLog?("发送命令失败：\(error.localizedDescription)") }
        else { onLog?("发送命令成功（设备已确认写入）") }
    }
}
