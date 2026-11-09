import SwiftUI

/// 设备页：整个 List 在强制深色下隐藏了系统背景，
/// 因此所有文字、按钮、分组标题都显式指定颜色，不再依赖系统语义色或 tint。
/// 依赖语义色会出现「深字深底 → 字看不见」。
struct DeviceView: View {
    @EnvironmentObject private var controller: WingController
    @State private var didInput = ""
    @State private var rawFrameInput = ""

    private var recentLogs: [LogEntry] { Array(controller.logs.prefix(20)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow(title: "状态", value: controller.connectionText)
                    statusRow(title: "已连接设备", value: controller.ble.connectedName ?? "—")
                    statusRow(title: "特征值", value: controller.ble.characteristicInfo)
                    if controller.ble.isUnsupported {
                        Text("iOS 模拟器不支持蓝牙低功耗，请开启下方「演示模式」查看完整交互。")
                            .font(.caption)
                            .foregroundStyle(Color.wingTextSecondary)
                    }
                } header: {
                    sectionHeader("连接状态")
                }

                Section {
                    Button("搜索设备") { controller.startScan() }
                        .foregroundStyle(Color.wingAccent)
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityLabel("搜索附近的尾翼控制器")
                        .accessibilityHint("第一次点击会申请蓝牙权限")

                    if controller.ble.cachedDeviceID != nil {
                        Button("连接上次使用的设备") { controller.connectCached() }
                            .foregroundStyle(Color.wingAccent)
                            .font(.body.weight(.medium))
                            .frame(minHeight: 44)
                            .accessibilityLabel("连接上次使用的设备")
                    }

                    Button("断开连接") { controller.disconnect() }
                        .foregroundStyle(Color.wingAccentWarm)
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityLabel("断开蓝牙连接")
                } header: {
                    sectionHeader("蓝牙操作")
                }

                Section {
                    if controller.ble.devices.isEmpty {
                        Text(controller.ble.phase == .scanning
                             ? "正在扫描附近的 JDY 蓝牙模块…"
                             : "暂无设备。点击上方「搜索设备」开始扫描。")
                            .font(.caption)
                            .foregroundStyle(Color.wingTextSecondary)
                    } else {
                        ForEach(controller.ble.devices) { device in
                            HStack(spacing: Spacing.xs) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.body)
                                        .foregroundStyle(Color.white)
                                    Text("信号 \(device.rssi) dBm · \(String(device.id.uuidString.prefix(8)))")
                                        .font(.caption)
                                        .foregroundStyle(Color.wingTextSecondary)
                                }
                                Spacer(minLength: Spacing.xs)
                                Button("连接") { controller.connect(device) }
                                    .buttonStyle(WingCapsuleButtonStyle(filled: true))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel("连接 \(device.name)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    sectionHeader("发现的设备")
                }

                Section {
                    Toggle("演示模式（无需硬件）", isOn: Binding(
                        get: { controller.demoMode },
                        set: { controller.setDemoMode($0) }
                    ))
                    .foregroundStyle(Color.white)
                    .tint(Color.wingAccent)
                    .frame(minHeight: 44)
                    .accessibilityLabel("演示模式")
                    .accessibilityHint("开启后所有指令在本地模拟，不需要真实尾翼控制器")

                    Toggle("模拟已安装车内实体按键", isOn: Binding(
                        get: { controller.demoHardwareButtonInstalled },
                        set: { controller.setDemoHardwareButton($0) }
                    ))
                    .foregroundStyle(Color.white)
                    .tint(Color.wingAccent)
                    .disabled(!controller.demoMode)
                    .frame(minHeight: 44)
                    .accessibilityLabel("模拟已安装车内实体按键")
                    .accessibilityHint("关闭后点火升降会返回操作失败")
                } header: {
                    sectionHeader("调试选项")
                }

                Section {
                    statusRow(title: "本机指令 ID (did)", value: controller.deviceIDHex)
                    statusRow(title: "设备回传 ID", value: controller.learnedDeviceIDHex ?? "—")
                    statusRow(title: "写入方式", value: controller.useWriteWithoutResponse ? "无响应写" : "带响应写")
                    statusRow(title: "上一条指令", value: controller.lastCommandHex.isEmpty ? "—" : controller.lastCommandHex)

                    Toggle("自动同步 did（对比测试时可关闭）", isOn: Binding(
                        get: { controller.autoSyncDeviceID },
                        set: { controller.setAutoSyncDeviceID($0) }
                    ))
                    .foregroundStyle(Color.white)
                    .tint(Color.wingAccent)
                    .frame(minHeight: 44)
                    .accessibilityLabel("自动同步指令 ID")
                    .accessibilityHint("关闭后设备状态帧不再覆盖手动指定的 did")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 手动指定 did（2 位十六进制，例如 1C）")
                            .font(.caption)
                            .foregroundStyle(Color.wingTextSecondary)
                        HStack(spacing: Spacing.xs) {
                            TextField("1C", text: $didInput)
                                .darkTextField()
                                .frame(maxWidth: 120)
                            Spacer(minLength: Spacing.xs)
                            Button("应用") { controller.setDeviceID(hex: didInput) }
                                .buttonStyle(WingCapsuleButtonStyle(filled: true))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.vertical, 2)

                    Toggle("无响应写（与微信小程序一致）", isOn: Binding(
                        get: { controller.useWriteWithoutResponse },
                        set: { controller.setWriteMode(withoutResponse: $0) }
                    ))
                    .foregroundStyle(Color.white)
                    .tint(Color.wingAccent)
                    .frame(minHeight: 44)
                    .accessibilityLabel("使用无响应写")
                    .accessibilityHint("关闭后改用带响应写，用于排查固件只认其中一种写法的情况")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("2. 直接发送原始帧（6 字节十六进制）")
                            .font(.caption)
                            .foregroundStyle(Color.wingTextSecondary)
                        HStack(spacing: Spacing.xs) {
                            TextField(controller.suggestedTestFrame, text: $rawFrameInput)
                                .darkTextField()
                                .font(.caption.monospaced())
                            Button("发送") {
                                controller.sendRawFrame(
                                    hex: rawFrameInput.isEmpty
                                        ? controller.suggestedTestFrame
                                        : rawFrameInput
                                )
                            }
                            .buttonStyle(WingCapsuleButtonStyle(filled: true))
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.vertical, 2)

                    // 这两行按钮原先完全依赖系统默认色，深色下文字与背景同色。
                    Button("重发上一条指令") { controller.resendLastFrame() }
                        .foregroundStyle(Color.wingAccent)
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityLabel("重发上一条指令")

                    Button("切换写入方式并重发") {
                        controller.setWriteMode(withoutResponse: !controller.useWriteWithoutResponse)
                        controller.resendLastFrame()
                    }
                    .foregroundStyle(Color.wingAccent)
                    .font(.body.weight(.medium))
                    .frame(minHeight: 44)
                    .accessibilityLabel("切换写入方式并重发上一条指令")

                    Text("先确认上方「演示模式」已关闭（开启时指令只在本地模拟，不会发到蓝牙）。设备每秒上报一次状态帧；若发指令后状态帧一直不变，说明设备忽略了命令：先让本机 did 与设备回传 ID 一致，再切换写入方式重试。状态帧不变会在日志里给出提示。")
                        .font(.caption)
                        .foregroundStyle(Color.wingTextSecondary)
                } header: {
                    sectionHeader("协议诊断：指令无反应时按顺序排查")
                }

                Section {
                    if recentLogs.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(Color.wingTextSecondary)
                    } else {
                        ForEach(recentLogs) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color.white)
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(Color.wingTextSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Button("清空日志") { controller.clearLogs() }
                        .foregroundStyle(Color.wingAccent)
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityLabel("清空命令日志")
                } header: {
                    sectionHeader("最近命令日志")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wingBackground)
            // 明确的深色行背景 + 高对比 tint，双保险：即使系统判错外观，字也不会消失
            .listRowBackground(Color.wingSurface)
            .tint(Color.wingAccent)
            .navigationTitle("设备")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.wingTextSecondary)
            .textCase(nil)
    }

    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text(title)
                .foregroundStyle(Color.wingTextSecondary)
            Spacer(minLength: Spacing.xs)
            Text(value)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.trailing)
                .font(.caption)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

/// `.roundedBorder` 在强制深色下可能给出浅底深字，这里用纯自定义样式锁死配色。
private extension View {
    func darkTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(Color.white)
            .tint(Color.wingAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Color.wingSurfaceAlt,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.wingBorder, lineWidth: 1)
            )
    }
}
