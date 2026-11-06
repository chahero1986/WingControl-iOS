import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var controller: WingController

    private var recentLogs: [LogEntry] { Array(controller.logs.prefix(20)) }

    var body: some View {
        NavigationStack {
            List {
                Section("连接状态") {
                    statusRow(title: "状态", value: controller.connectionText)
                    statusRow(title: "已连接设备", value: controller.ble.connectedName ?? "—")
                    statusRow(title: "特征值", value: controller.ble.characteristicInfo)
                    if controller.ble.isUnsupported {
                        Text("iOS 模拟器不支持蓝牙低功耗，请开启下方「演示模式」查看完整交互。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("蓝牙操作") {
                    Button("搜索设备") { controller.startScan() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("搜索附近的尾翼控制器")
                        .accessibilityHint("第一次点击会申请蓝牙权限")

                    if controller.ble.cachedDeviceID != nil {
                        Button("连接上次使用的设备") { controller.connectCached() }
                            .frame(minHeight: 44)
                            .accessibilityLabel("连接上次使用的设备")
                    }

                    Button("断开连接", role: .destructive) { controller.disconnect() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("断开蓝牙连接")
                }

                Section("发现的设备") {
                    if controller.ble.devices.isEmpty {
                        Text(controller.ble.phase == .scanning
                             ? "正在扫描附近的 JDY 蓝牙模块…"
                             : "暂无设备。点击上方「搜索设备」开始扫描。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.ble.devices) { device in
                            HStack(spacing: Spacing.xs) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.body)
                                    Text("信号 \(device.rssi) dBm · \(String(device.id.uuidString.prefix(8)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: Spacing.xs)
                                Button("连接") { controller.connect(device) }
                                    .buttonStyle(.borderedProminent)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("连接 \(device.name)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("调试选项") {
                    Toggle("演示模式（无需硬件）", isOn: Binding(
                        get: { controller.demoMode },
                        set: { controller.setDemoMode($0) }
                    ))
                    .frame(minHeight: 44)
                    .accessibilityLabel("演示模式")
                    .accessibilityHint("开启后所有指令在本地模拟，不需要真实尾翼控制器")

                    Toggle("模拟已安装车内实体按键", isOn: Binding(
                        get: { controller.demoHardwareButtonInstalled },
                        set: { controller.setDemoHardwareButton($0) }
                    ))
                    .disabled(!controller.demoMode)
                    .frame(minHeight: 44)
                    .accessibilityLabel("模拟已安装车内实体按键")
                    .accessibilityHint("关闭后点火升降会返回操作失败")
                }

                Section("最近命令日志") {
                    if recentLogs.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentLogs) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .font(.caption.monospaced())
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Button("清空日志") { controller.clearLogs() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("清空命令日志")
                }
            }
            .navigationTitle("设备")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs)
            Text(value)
                .multilineTextAlignment(.trailing)
                .font(.caption)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}
