import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var controller: WingController
    @State private var selection: Tab = .control

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case control, device, info

        var id: String { rawValue }

        var title: String {
            switch self {
            case .control: return "控制"
            case .device: return "设备"
            case .info: return "说明"
            }
        }

        var symbol: String {
            switch self {
            case .control: return "slider.horizontal.3"
            case .device: return "antenna.radiowaves.left.and.right"
            case .info: return "info.circle.fill"
            }
        }

        /// 三个标签各自一个高饱和色，选中时图标与文字都一定看得见
        var tint: Color {
            switch self {
            case .control: return .wingControlTint
            case .device: return .wingDeviceTint
            case .info: return .wingInfoTint
            }
        }
    }

    var body: some View {
        Group {
            switch selection {
            case .control:
                ControlView(openDevices: { selection = .device })
            case .device:
                DeviceView()
            case .info:
                InfoView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wingBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        // 系统 UIAlertController 的按钮文字由 tint 决定，在强制深色主题下
        // 可能与弹窗背景同色而「按钮在、字没了」。改用完全自控的 SwiftUI 弹层。
        .overlay {
            if let item = controller.alertItem {
                WingAlertOverlay(
                    item: item,
                    dismiss: { controller.alertItem = nil },
                    confirmCalibration: { controller.confirmCalibration() }
                )
            }
        }
        .sheet(item: $controller.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(controller)
        }
    }

    /// 自定义底部栏：不用系统 TabView 的 tint，避免选中项图标「消失」；
    /// 每个标签有独立的彩色高亮 + 半透明色块 + 描边。
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                    Haptics.selection()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(selection == tab ? tab.tint : Color.wingTabInactive)
                        Text(tab.title)
                            .font(.caption2.weight(selection == tab ? .bold : .medium))
                            .foregroundStyle(selection == tab ? tab.tint : Color.wingTabInactive)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == tab ? tab.tint.opacity(0.18) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selection == tab ? tab.tint.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.title)，标签页")
                .accessibilityValue(selection == tab ? "已选中" : "未选中")
            }
        }
        .padding(.vertical, 6)
        .background(Color.wingTabBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.wingBorder.opacity(0.7))
                .frame(height: 1)
        }
    }
}

// MARK: - 提示弹层（完全自控配色，不依赖系统 UIAlertController）

/// 取代 `.alert(item:)`：系统弹窗按钮文字颜色由 tint 决定，深色主题下
/// 曾出现「按钮在、字是空白」。这里所有文字与按钮都显式指定高对比颜色。
private struct WingAlertOverlay: View {
    let item: WingAlertItem
    let dismiss: () -> Void
    let confirmCalibration: () -> Void

    private var isCalibration: Bool {
        if case .calibration = item { return true }
        return false
    }

    private var title: String {
        isCalibration ? "进入校准模式" : "提示"
    }

    private var message: String {
        switch item {
        case .info(let text): return text
        case .calibration: return "升降速度都设置为0将进入校准模式，您确认要进入校准模式吗？"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.wingTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: Spacing.xs) {
                    if isCalibration {
                        Button("取消") { dismiss() }
                            .buttonStyle(WingCapsuleButtonStyle())
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("取消进入校准模式")
                    }
                    Button("确定") {
                        if isCalibration { confirmCalibration() }
                        dismiss()
                    }
                    .buttonStyle(WingCapsuleButtonStyle(filled: true))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("确定")
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: 320)
            .background(
                Color.wingSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wingBorder, lineWidth: 1)
            )
            .padding(Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }
}

// MARK: - 弹层宿主（sheet 自带下滑关闭手势 + 显式关闭按钮）

struct SheetHost: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetent: PresentationDetent
    let sheet: WingSheet

    init(sheet: WingSheet) {
        self.sheet = sheet
        // 说明类弹层文字较长，默认展开到大尺寸，避免半屏时看不全
        let fullHeight: Bool
        switch sheet {
        case .autoHint, .trackHint: fullHeight = true
        case .ignitionSuccess, .ignitionFailure: fullHeight = false
        }
        _selectedDetent = State(initialValue: fullHeight ? .large : .medium)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    content
                }
                .padding(Spacing.sm)
            }
            .background(Color.wingBackground)
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.wingAccent)
                        .accessibilityLabel("关闭弹窗")
                }
            }
        }
        .background(Color.wingBackground)
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .autoHint:
            AutoHintContent()
        case .trackHint:
            TrackHintContent()
        case .ignitionSuccess:
            IgnitionSuccessContent()
        case .ignitionFailure:
            IgnitionFailureContent()
        }
    }
}

// MARK: - 各弹层内容

private struct AutoHintContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("车速降低小于指定码数后触发尾翼下降")
                .font(.body)
                .foregroundStyle(.white)
            Text("车速提高大于指定码数后触发尾翼升起")
                .font(.body)
                .foregroundStyle(.white)
            Divider()
            Text("注：降速加速临界范围总大于 20 码")
                .font(.footnote)
                .foregroundStyle(Color.wingTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.wingSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("自动升降模式说明：车速降低小于指定码数后触发尾翼下降，车速提高大于指定码数后触发尾翼升起。降速加速临界范围总大于 20 码。")
    }
}

private struct TrackHintContent: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image("TrackDialog")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 200)
                .clipped()
                .accessibilityLabel("赛道模式示意图")
            Text("车辆大幅度降速(加速度a由正转为负，当a触达设定条件时)将使尾翼进一步升起(持续5s)，增加持续时间内车体的下压力，进而加强减速时车身抓地力。")
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("我知道了") { dismiss() }
                .buttonStyle(WingCapsuleButtonStyle(filled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("我知道了，关闭说明")
        }
    }
}

private struct IgnitionSuccessContent: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image("FireSuccess")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipped()
                .accessibilityLabel("操作成功")
            Text("成功执行了一次点火升降后的升降动作")
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            AnimatedImageView(prefix: "FireAnim", frameCount: 4, duration: 1.2)
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
                .clipped()
                .accessibilityHidden(true)
            Button("返回") { dismiss() }
                .buttonStyle(WingCapsuleButtonStyle(filled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("返回控制页面")
        }
    }
}

private struct IgnitionFailureContent: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image("FireFailure")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipped()
                .accessibilityLabel("操作失败")
            Text("点火升降操作失败！")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("需在车内安装实体按键才可完成操作")
                .font(.body)
                .foregroundStyle(Color.wingTextSecondary)
            Button("我知道了") { dismiss() }
                .buttonStyle(WingCapsuleButtonStyle(filled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("我知道了，关闭提示")
        }
    }
}
