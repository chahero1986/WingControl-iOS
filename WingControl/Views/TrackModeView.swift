import SwiftUI

/// 赛道模式：按用户要求移除「演示动画 / 演示视频」模块，
/// 只保留刹车幅度设定与强 / 中 / 弱三档。
struct TrackModeView: View {
    @EnvironmentObject private var controller: WingController

    private struct TrackOption: Identifiable {
        let id: Int
        let title: String
    }

    private let options: [TrackOption] = [
        TrackOption(id: 1, title: "强"),
        TrackOption(id: 2, title: "中"),
        TrackOption(id: 3, title: "弱")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                SectionHeader("刹车幅度设定", subtitle: "幅度越强越容易触发")
                Spacer(minLength: Spacing.xs)
                InfoButton(label: "赛道模式说明") {
                    controller.sheet = .trackHint
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)

            Text("a = \(controller.state.intensity) m/s²")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.wingAccent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("当前加速度阈值 \(controller.state.intensity) 米每二次方秒")

            HStack(spacing: Spacing.xs) {
                ForEach(options) { option in
                    Button(option.title) { controller.setTrackType(option.id) }
                        .buttonStyle(WingCapsuleButtonStyle(active: controller.state.trackType == option.id))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("刹车灵敏度 \(option.title)")
                        .accessibilityValue(controller.state.trackType == option.id ? "已选中" : "未选中")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            Color.wingSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wingBorder.opacity(0.8), lineWidth: 1)
        )
    }
}
