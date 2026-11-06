import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var controller: WingController
    @State private var selection: Tab = .control

    enum Tab: Hashable {
        case control, device, info
    }

    var body: some View {
        TabView(selection: $selection) {
            ControlView(openDevices: { selection = .device })
                .tabItem { Label("控制", systemImage: "slider.horizontal.3") }
                .tag(Tab.control)
                .accessibilityLabel("控制，标签页")

            DeviceView()
                .tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(Tab.device)
                .accessibilityLabel("设备，标签页")

            InfoView()
                .tabItem { Label("说明", systemImage: "info.circle") }
                .tag(Tab.info)
                .accessibilityLabel("说明，标签页")
        }
        .sheet(item: $controller.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(controller)
        }
        .alert(item: $controller.alertItem) { item in
            switch item {
            case .info(let message):
                return Alert(
                    title: Text("提示"),
                    message: Text(message),
                    dismissButton: .default(Text("确定"))
                )
            case .calibration:
                return Alert(
                    title: Text("进入校准模式"),
                    message: Text("升降速度都设置为0将进入校准模式，您确认要进入校准模式吗？"),
                    primaryButton: .default(Text("确定")) { controller.confirmCalibration() },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
}

// MARK: - 弹层宿主（sheet 自带下滑关闭手势 + 显式关闭按钮）

struct SheetHost: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: WingSheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    content
                }
                .padding(Spacing.sm)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityLabel("关闭弹窗")
                }
            }
        }
        .presentationDetents([.medium, .large])
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
            Text("车速提高大于指定码数后触发尾翼升起")
                .font(.body)
            Divider()
            Text("注：降速加速临界范围总大于 20 码")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
                .frame(maxHeight: 200)
                .accessibilityLabel("赛道模式示意图")
            Text("车辆大幅度降速(加速度a由正转为负，当a触达设定条件时)将使尾翼进一步升起(持续5s)，增加持续时间内车体的下压力，进而加强减速时车身抓地力。")
                .font(.body)
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
                .frame(maxHeight: 180)
                .accessibilityLabel("操作成功")
            Text("成功执行了一次点火升降后的升降动作")
                .font(.body)
                .multilineTextAlignment(.center)
            AnimatedImageView(prefix: "FireAnim", frameCount: 4, duration: 1.2)
                .frame(height: 100)
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
                .frame(maxHeight: 180)
                .accessibilityLabel("操作失败")
            Text("点火升降操作失败！")
                .font(.title3.weight(.bold))
            Text("需在车内安装实体按键才可完成操作")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("我知道了") { dismiss() }
                .buttonStyle(WingCapsuleButtonStyle(filled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("我知道了，关闭提示")
        }
    }
}
