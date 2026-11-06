import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var controller: WingController
    let openDevices: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ConnectionBanner(openDevices: openDevices)
                    modePicker
                    if controller.state.mode == .daily {
                        DailyModeView()
                    } else {
                        TrackModeView()
                    }
                    FooterBar()
                }
                .padding(Spacing.sm)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("尾翼控制器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: openDevices) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .accessibilityHidden(true)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("搜索蓝牙设备")
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("控制模式", selection: Binding(
            get: { controller.state.mode },
            set: { controller.setMode($0) }
        )) {
            ForEach(WingMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("控制模式")
        .accessibilityHint("日常模式用于手动与自动升降，赛道模式用于刹车灵敏度设定")
    }
}

// MARK: - 底部品牌栏 + 点火升降

private struct FooterBar: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("尾翼控制器")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text("WING CONTROL")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("尾翼控制器")

            Spacer(minLength: Spacing.xs)

            Button {
                controller.toggleIgnition()
            } label: {
                Text(controller.state.ignitionTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(WingCapsuleButtonStyle(filled: controller.state.ignitionOn, onDark: true))
            .frame(maxWidth: 190, minHeight: 44)
            .accessibilityLabel(controller.state.ignitionTitle)
            .accessibilityValue(controller.state.ignitionReady ? "功能可用" : "功能不可用，需安装车内实体按键")
        }
        .padding(Spacing.xs)
        .background(Color.wingCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
