import SwiftUI

struct DailyModeView: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            WingCanvas()
            OneKeyRow()
            AutoCard()
        }
    }
}

// MARK: - 尾翼状态画布

private struct WingCanvas: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        DarkCanvas {
            VStack(spacing: Spacing.xs) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    StepLadder()
                    Image(controller.state.stepAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .accessibilityLabel("尾翼车身示意图，当前档位 \(controller.state.step)，最高 5 档")
                }
                StatusStrip()
            }
        }
    }
}

private struct StepLadder: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Button("升") { controller.stepUp() }
                .buttonStyle(WingCapsuleButtonStyle(onDark: true))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("升高一档")
                .accessibilityHint("在当前档位上升一级")

            ForEach([5, 4, 3], id: \.self) { value in
                Button("\(value)") { controller.setStep(value) }
                    .buttonStyle(WingCapsuleButtonStyle(active: controller.state.step >= value, onDark: true))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("设置尾翼档位为 \(value)")
                    .accessibilityValue(controller.state.step >= value ? "已选中" : "未选中")
            }

            Button("降") { controller.stepDown() }
                .buttonStyle(WingCapsuleButtonStyle(onDark: true))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("降低一档")
                .accessibilityHint("在当前档位下降一级")
        }
    }
}

private struct StatusStrip: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Label(
                "尾翼已升起 · 档位 \(controller.state.step)/5",
                systemImage: controller.state.isDescending ? "arrow.down.circle" : "arrow.up.circle"
            )
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: Spacing.xs)
            Text("车速 \(controller.state.speed) km/h")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("尾翼档位 \(controller.state.step)，设备上报车速 \(controller.state.speed) 公里每小时")
    }
}

// MARK: - 一键上升 / 一键下降

private struct OneKeyRow: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button { controller.oneKey(true) } label: {
                Image("UpButton")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 96)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("一键上升")
            .accessibilityHint("把尾翼直接升到 5 档")

            Button { controller.oneKey(false) } label: {
                Image("DownButton")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 96)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("一键下降")
            .accessibilityHint("把尾翼直接降到 0 档")
        }
    }
}

// MARK: - AUTO 自动升降

private struct AutoCard: View {
    @EnvironmentObject private var controller: WingController

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("AUTO")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.wingAccent)
                InfoButton(label: "自动升降模式说明") {
                    controller.sheet = .autoHint
                }
                Spacer(minLength: Spacing.xs)
                Toggle("自动升降模式", isOn: Binding(
                    get: { controller.state.isAuto },
                    set: { controller.setAuto($0) }
                ))
                .labelsHidden()
                .accessibilityLabel("自动升降模式")
                .accessibilityValue(controller.state.isAuto ? "已开启" : "已关闭")
            }

            if controller.state.isAuto {
                HStack(spacing: Spacing.sm) {
                    Text("降速/加速临界")
                        .font(.caption)
                        .foregroundStyle(Color.wingTextSecondary)
                        .frame(maxWidth: .infinity)
                    Text("尾翼下降/升起")
                        .font(.caption)
                        .foregroundStyle(Color.wingTextSecondary)
                        .frame(maxWidth: .infinity)
                }
                SpeedWheelPair(
                    downValues: WingProtocol.downSpeeds,
                    upValues: WingProtocol.upSpeeds,
                    downIndex: controller.state.downIndex,
                    upIndex: controller.state.upIndex,
                    revision: controller.speedPickerRevision,
                    onChange: { down, up in
                        controller.updateSpeeds(downIndex: down, upIndex: up)
                        return (controller.state.downIndex, controller.state.upIndex)
                    }
                )
                .frame(height: 120)
                .clipped()
                .accessibilityLabel("自动升降速度临界，左列降速临界，右列升速临界")

                HStack(spacing: Spacing.xs) {
                    Spacer()
                    Button("进入校准模式") { controller.requestCalibration() }
                        .buttonStyle(WingCapsuleButtonStyle(filled: true))
                        .frame(minHeight: 44)
                        .accessibilityLabel("进入校准模式")
                        .accessibilityHint("把两列速度临界都设为 0，需二次确认")
                }
                Text("注：降速加速临界范围总大于 20 码；两列同时设为 0 将进入校准模式。")
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("开启后尾翼按车速自动升降；关闭时可用上方档位按钮手动控制。")
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

