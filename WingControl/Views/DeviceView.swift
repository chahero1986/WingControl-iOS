import SwiftUI

/// 设备页：整个 List 在强制深色下隐藏了系统背景，
/// 因此所有文字、按钮、分组标题都显式指定颜色，不再依赖系统语义色或 tint。
/// 依赖语义色会出现「深字深底 → 字看不见」。
struct DeviceView: View {
    @EnvironmentObject private var controller: WingController
    @State private var didInput = ""
    @State private var rawFrameInput = ""
    @State private var showTestPanel = false

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
                    Text("自动依次尝试所有可能的发送组合：每个可写特征值 × 带/不带响应 × 帧内容与长度变体 × 指令 ID。每项停留约 2 秒，界面显示大号编号；看到尾翼动作就记下编号，或直接点面板里的「这个编号有效」。")
                        .font(.caption)
                        .foregroundStyle(Color.wingTextSecondary)
                    statusRow(title: "已发现可写通道", value: "\(controller.ble.writeTargets.count) 个")
                    statusRow(title: "全部特征值", value: controller.ble.allCharacteristicInfo)
                    Button("打开一键协议测试") { showTestPanel = true }
                        .foregroundStyle(Color.white)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.wingAccentGradient, in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开一键协议测试")
                        .accessibilityHint("自动遍历所有可能的蓝牙指令组合，只需记下有效的编号")
                } header: {
                    sectionHeader("一键协议测试（指令无反应时，直接用它定位）")
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
            .sheet(isPresented: $showTestPanel) {
                WingTestPanel(runner: controller.testRunner)
                    .environmentObject(controller)
            }
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

// MARK: - 一键协议测试面板

/// 大号编号 + 逐项自动发送 + 一键标记成功 + 可复制报告。
/// 所有文字显式着色，避免在强制深色下出现「按钮在、字是空白」。
struct WingTestPanel: View {
    @EnvironmentObject private var controller: WingController
    @ObservedObject var runner: WingTestRunner
    @Environment(\.dismiss) private var dismiss

    private var successText: String {
        runner.successIDs.sorted().map { "#\($0)" }.joined(separator: "  ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    headerCard
                    controlCard
                    resultCard
                    tipCard
                }
                .padding(Spacing.sm)
            }
            .scrollContentBackground(.hidden)
            .background(Color.wingBackground)
            .navigationTitle("一键协议测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        runner.stop()
                        dismiss()
                    }
                    .foregroundStyle(Color.wingAccent)
                    .accessibilityLabel("关闭测试面板")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 当前编号卡片

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(runner.currentIndex)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.wingAccent)
                    .accessibilityLabel("当前测试编号 \(runner.currentIndex)")
                Spacer(minLength: Spacing.xs)
                Text("共 \(runner.cases.count) 项")
                    .font(.subheadline)
                    .foregroundStyle(Color.wingTextSecondary)
            }
            progressBar
            Text(runner.statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
            if let item = runner.currentCase {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text(item.frameHex)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.wingAccent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.channelText)
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
            } else {
                Text("点下方「开始标准矩阵」，然后盯住尾翼。看到动作就记下这个大号编号。")
                    .font(.subheadline)
                    .foregroundStyle(Color.wingTextSecondary)
            }
            if !runner.successIDs.isEmpty {
                Text("已标记成功：\(successText)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.wingDeviceTint)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.wingSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wingBorder, lineWidth: 1)
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.wingSurfaceAlt)
                Capsule()
                    .fill(Color.wingAccent)
                    .frame(width: max(0, geo.size.width * CGFloat(runner.progress)))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("测试进度 \(Int(runner.progress * 100))%")
    }

    // MARK: 控制按钮

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("运行控制")
                .font(.headline)
                .foregroundStyle(Color.white)
            HStack(spacing: Spacing.xs) {
                actionButton("开始标准矩阵", filled: true) { runner.start(mode: .standard) }
                actionButton("did 全扫描", filled: false) { runner.start(mode: .didScan) }
            }
            HStack(spacing: Spacing.xs) {
                actionButton(runner.isRunning ? "暂停" : "继续", filled: false) {
                    if runner.isRunning { runner.pause() } else { runner.resume() }
                }
                actionButton("单步下一项", filled: false) { runner.stepForward() }
            }
            HStack(spacing: Spacing.xs) {
                actionButton("重发当前编号", filled: false) { runner.restartCurrent() }
                actionButton("停止 / 重置", filled: false) { runner.reset() }
            }
            Button(action: { runner.markSuccess() }) {
                Text("★ 这个编号有效（尾翼动了）")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.wingAccentGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("标记当前编号有效")
            .accessibilityHint("看到尾翼动作后点这里，编号会写进测试报告")
            actionButton("复制测试报告（发给开发者）", filled: true) { runner.copyReport() }
            if runner.reportCopied {
                Text("报告已复制到剪贴板，粘贴到微信 / 备忘录即可发送。")
                    .font(.caption)
                    .foregroundStyle(Color.wingDeviceTint)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.wingSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wingBorder, lineWidth: 1)
        )
    }

    private func actionButton(
        _ title: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(capsuleFill(filled: filled), in: Capsule())
                .overlay(Capsule().stroke(Color.wingBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func capsuleFill(filled: Bool) -> LinearGradient {
        if filled { return Color.wingAccentGradient }
        return LinearGradient(
            colors: [Color.wingSurfaceAlt, Color.wingSurfaceAlt],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: 执行记录

    private var recentResults: [WingTestResult] {
        Array(runner.results.reversed().prefix(40))
    }

    private func resultDetail(_ result: WingTestResult) -> String {
        let verdict = result.telemetryChanged ? "状态帧变化" : "状态帧未变化"
        return result.channel + " · " + verdict
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("执行记录（最近 40 条）")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Spacer(minLength: Spacing.xs)
                Text("自动判定仅供参考")
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
            }
            if recentResults.isEmpty {
                Text("还没有执行记录。完整明细都在「复制测试报告」里。")
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
            } else {
                ForEach(recentResults) { result in
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Text("#\(result.caseID)")
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(result.userMarked ? Color.wingDeviceTint : Color.wingAccent)
                            .frame(minWidth: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white)
                            Text(result.frameHex)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.wingTextSecondary)
                            Text(resultDetail(result))
                                .font(.caption2)
                                .foregroundStyle(
                                    result.telemetryChanged
                                        ? Color.wingDeviceTint
                                        : Color.wingTextSecondary
                                )
                            if result.userMarked {
                                Text("★ 已标记为有效")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.wingDeviceTint)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.wingSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wingBorder, lineWidth: 1)
        )
    }

    // MARK: 使用说明

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("怎么记结果")
                .font(.headline)
                .foregroundStyle(Color.white)
            Text("1. 先关闭「演示模式」并连上蓝牙，站在能看到尾翼的位置。\n2. 点「开始标准矩阵」，界面每约 2 秒换一个编号（#1、#2……）。\n3. 看到尾翼动了，立刻点「这个编号有效」，或把编号记在纸上。\n4. 跑完点「复制测试报告」粘贴发我，报告含每项的帧、写入通道与自动判定。\n5. 标准矩阵全无效时，再跑「did 全扫描」：0x00~0xFF 逐个试，约 3 分钟。")
                .font(.caption)
                .foregroundStyle(Color.wingTextSecondary)
            Text("注意：状态帧未变化不等于一定失败，最终以你亲眼看到尾翼动作的编号为准。")
                .font(.caption)
                .foregroundStyle(Color.wingTextSecondary)
            Text("当前连接：\(controller.connectionText)")
                .font(.caption)
                .foregroundStyle(Color.wingTextSecondary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.wingSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wingBorder, lineWidth: 1)
        )
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
