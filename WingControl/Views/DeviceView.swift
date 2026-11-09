import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var controller: WingController
    @State private var didInput = ""
    @State private var rawFrameInput = ""

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

                Section("协议诊断：指令无反应时按顺序排查") {
                    statusRow(title: "本机指令 ID (did)", value: controller.deviceIDHex)
                    statusRow(title: "设备回传 ID", value: controller.learnedDeviceIDHex ?? "—")
                    statusRow(title: "写入方式", value: controller.useWriteWithoutResponse ? "无响应写" : "带响应写")
                    statusRow(title: "上一条指令", value: controller.lastCommandHex.isEmpty ? "—" : controller.lastCommandHex)

                    Toggle("自动同步 did（对比测试时可关闭）", isOn: Binding(
                        get: { controller.autoSyncDeviceID },
                        set: { controller.setAutoSyncDeviceID($0) }
                    ))
                    .frame(minHeight: 44)
                    .accessibilityLabel("自动同步指令 ID")
                    .accessibilityHint("关闭后设备状态帧不再覆盖手动指定的 did")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 手动指定 did（2 位十六进制，例如 1C）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: Spacing.xs) {
                            TextField("1C", text: $didInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                            Spacer(minLength: Spacing.xs)
                            Button("应用") { controller.setDeviceID(hex: didInput) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.vertical, 2)

                    Toggle("无响应写（与微信小程序一致）", isOn: Binding(
                        get: { controller.useWriteWithoutResponse },
                        set: { controller.setWriteMode(withoutResponse: $0) }
                    ))
                    .frame(minHeight: 44)
                    .accessibilityLabel("使用无响应写")
                    .accessibilityHint("关闭后改用带响应写，用于排查固件只认其中一种写法的情况")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("2. 直接发送原始帧（6 字节十六进制）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: Spacing.xs) {
                            TextField(controller.suggestedTestFrame, text: $rawFrameInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                            Button("发送") {
                                controller.sendRawFrame(
                                    hex: rawFrameInput.isEmpty
                                        ? controller.suggestedTestFrame
                                        : rawFrameInput
                                )
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.vertical, 2)

                    Button("重发上一条指令") { controller.resendLastFrame() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("重发上一条指令")

                    Button("切换写入方式并重发") {
                        controller.setWriteMode(withoutResponse: !controller.useWriteWithoutResponse)
                        controller.resendLastFrame()
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("切换写入方式并重发上一条指令")

                    Text("先确认上方「演示模式」已关闭（开启时指令只在本地模拟，不会发到蓝牙）。设备每秒上报一次状态帧；若发指令后状态帧一直不变，说明设备忽略了命令：先让本机 did 与设备回传 ID 一致，再切换写入方式重试。状态帧不变会在日志里给出提示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .scrollContentBackground(.hidden)
            .background(Color.wingBackground)
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
