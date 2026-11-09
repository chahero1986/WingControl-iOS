import SwiftUI
import UIKit

// MARK: - 深色画布卡片

struct DarkCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            // 明确占满容器宽度，避免 UIViewRepresentable 等自带固有尺寸的子视图横向撑破卡片
            .frame(maxWidth: .infinity)
            .padding(Spacing.sm)
            .background(Color.wingCanvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wingBorder, lineWidth: 1)
            )
    }
}

// MARK: - 胶囊按钮样式

struct WingCapsuleButtonStyle: ButtonStyle {
    var active: Bool = false
    var filled: Bool = false
    /// 用于深色控制画布上的按钮，保证对比度 ≥ 4.5:1
    var onDark: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(minHeight: 44)
            .padding(.horizontal, Spacing.sm)
            .background(capsule)
            .overlay(
                Capsule().stroke(
                    active || filled ? Color.white.opacity(0.35) : Color.wingBorder.opacity(0.9),
                    lineWidth: 1
                )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }

    /// 选中态一律「彩色渐变 + 纯白粗体字」：不依赖系统 accentColor，
    /// 也不会出现「选中后文字与背景同色、字看不见」的情况。
    private var foreground: Color {
        if active || filled { return .white }
        return .white.opacity(0.92)
    }

    @ViewBuilder
    private var capsule: some View {
        if active || filled {
            Capsule().fill(Color.wingAccentGradient)
        } else {
            Capsule().fill(onDark ? Color.white.opacity(0.14) : Color.wingSurfaceAlt)
        }
    }
}

// MARK: - 连接状态横幅

struct ConnectionBanner: View {
    @EnvironmentObject private var controller: WingController
    let openDevices: () -> Void

    var body: some View {
        Button(action: openDevices) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: controller.isConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                    .font(.title3)
                    .foregroundStyle(controller.isConnected ? Color.wingAccent : Color.wingTextSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.connectionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(controller.isConnected ? "点击管理已连接的设备" : "点击前往「设备」页搜索并连接")
                        .font(.caption)
                        .foregroundStyle(Color.wingTextSecondary)
                }

                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.sm)
            .frame(minHeight: 56)
            .background(
                Color.wingSurface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.wingBorder.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("蓝牙连接状态：\(controller.connectionText)")
        .accessibilityHint("双击打开设备管理")
    }
}

// MARK: - 说明按钮

struct InfoButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("InfoIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityHint("双击查看功能说明")
    }
}

// MARK: - 小节标题

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.wingTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GIF 逐帧动画（遵守「减弱动态效果」）

struct AnimatedImageView: UIViewRepresentable {
    let prefix: String
    let frameCount: Int
    let duration: TimeInterval
    var play: Bool = true

    func makeUIView(context: Context) -> UIImageView {
        // 只设置 animationImages 时 UIImageView 的 intrinsicContentSize 是
        // noIntrinsicMetric；原帧 710pt 宽会把父容器撑出屏幕（赛道页看不全）。
        // 先放静态首帧让固有尺寸有效，再降低内容吸附/压缩优先级，
        // 由 SwiftUI 的父容器决定实际尺寸。
        let images = frames()
        let imageView = UIImageView(image: images.first)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = false
        imageView.backgroundColor = .clear
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        apply(images, to: imageView)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let shouldAnimate = play && !UIAccessibility.isReduceMotionEnabled
        // 状态没变就不要重复装载图片，避免 SwiftUI 刷新时反复 startAnimating
        if shouldAnimate {
            guard !imageView.isAnimating else { return }
        } else {
            guard imageView.isAnimating || imageView.animationImages != nil else { return }
        }
        apply(frames(), to: imageView)
    }

    private func apply(_ images: [UIImage], to imageView: UIImageView) {
        imageView.stopAnimating()
        imageView.animationImages = nil
        imageView.image = images.first
        guard !images.isEmpty, play, !UIAccessibility.isReduceMotionEnabled else { return }
        imageView.animationImages = images
        imageView.animationDuration = duration
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
    }

    private func frames() -> [UIImage] {
        (0..<frameCount).compactMap { UIImage(named: "\(prefix)\($0)") }
    }
}

// MARK: - 双列速度滚轮（对应原小程序 picker-view）

/// 用 UIPickerView 实现两列滚轮：didSelectRow 一次读取两列的值，
/// 与原小程序 `bindChangeleft(e.detail.value[0], value[1])` 的行为一致。
struct SpeedWheelPair: UIViewRepresentable {
    let downValues: [Int]
    let upValues: [Int]
    let downIndex: Int
    let upIndex: Int
    /// 每次选择后自增，用于把滚轮回弹到合法值
    let revision: Int
    /// 返回校验后应当显示的 (downIndex, upIndex)
    let onChange: (Int, Int) -> (Int, Int)

    func makeCoordinator() -> Coordinator {
        Coordinator(downValues: downValues, upValues: upValues, onChange: onChange)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.accessibilityLabel = "自动升降速度临界，双列滚轮选择器"
        picker.selectRow(downIndex, inComponent: 0, animated: false)
        picker.selectRow(upIndex, inComponent: 1, animated: false)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.onChange = onChange
        if picker.selectedRow(inComponent: 0) != downIndex {
            picker.selectRow(downIndex, inComponent: 0, animated: true)
        }
        if picker.selectedRow(inComponent: 1) != upIndex {
            picker.selectRow(upIndex, inComponent: 1, animated: true)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        let downValues: [Int]
        let upValues: [Int]
        var onChange: (Int, Int) -> (Int, Int)

        init(
            downValues: [Int],
            upValues: [Int],
            onChange: @escaping (Int, Int) -> (Int, Int)
        ) {
            self.downValues = downValues
            self.upValues = upValues
            self.onChange = onChange
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? downValues.count : upValues.count
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = component == 0 ? "\(downValues[row]) km/h" : "\(upValues[row]) km/h"
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .white
            label.textAlignment = .center
            label.isAccessibilityElement = true
            label.accessibilityLabel = label.text
            return label
        }

        func pickerView(
            _ pickerView: UIPickerView,
            didSelectRow row: Int,
            inComponent component: Int
        ) {
            let down = pickerView.selectedRow(inComponent: 0)
            let up = pickerView.selectedRow(inComponent: 1)
            let accepted = onChange(down, up)
            if pickerView.selectedRow(inComponent: 0) != accepted.0 {
                pickerView.selectRow(accepted.0, inComponent: 0, animated: true)
            }
            if pickerView.selectedRow(inComponent: 1) != accepted.1 {
                pickerView.selectRow(accepted.1, inComponent: 1, animated: true)
            }
        }
    }
}
