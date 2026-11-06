import SwiftUI

struct TrackModeView: View {
    @EnvironmentObject private var controller: WingController
    @State private var playAnimation = true

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
        VStack(spacing: Spacing.sm) {
            DarkCanvas {
                VStack(spacing: Spacing.xs) {
                    Button {
                        playAnimation.toggle()
                        Haptics.selection()
                    } label: {
                        AnimatedImageView(
                            prefix: "TrackAnim",
                            frameCount: 8,
                            duration: 1.6,
                            play: playAnimation
                        )
                        .frame(height: 150)
                        .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("赛道模式动画")
                    .accessibilityHint(playAnimation ? "双击暂停动画" : "双击播放动画")

                    Image("TrackStatus")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 56)
                        .accessibilityLabel("赛道模式启用中，尾翼已升起")
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    SectionHeader("刹车幅度设定", subtitle: "幅度越强越容易触发")
                    Spacer(minLength: Spacing.xs)
                    InfoButton(label: "赛道模式说明") {
                        controller.sheet = .trackHint
                    }
                }

                Text("a = \(controller.state.intensity) m/s²")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            }
            .padding(Spacing.sm)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }
}
