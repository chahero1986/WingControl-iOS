#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 源码静态预检（无需 Xcode，Windows / macOS / Linux 均可运行）。

本机没有 Swift 编译器，GitHub Actions 上才第一次真正编译。这个脚本把已经
踩过的、以及容易再犯的编译期问题在提交前拦住：

  1. SwiftUI `.frame(...)` 的两个重载不能混用
     - frame(width:height:alignment:)
     - frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)
     `width` / `height` 与任何 min/ideal/max 参数同用会报
     "extra argument 'minHeight' in call"。
  2. 字符串插值里直接放 Substring（.prefix/.suffix/...）在
     LocalizedStringKey 上没有对应 appendInterpolation 重载，需要 String(...)。
  3. 项目约定：可选绑定一律写 `guard let self = self`，不用 Swift 5.7 简写。
  4. 括号平衡、旧应用名残留。
  5. 启动链路：Info.plist 的场景清单必须指向 SceneDelegate，且全工程只能有
     一个应用入口、启动屏不能是近黑色（否则启动失败时表现为黑屏）；
     手写 Info.plist 还必须显式声明 CFBundleIconName，资源目录要进 Resources
     构建阶段，否则 Assets.car 用不上、桌面图标空白。
  6. `AnimatedImageView` 是 UIViewRepresentable，帧原图 710pt 宽，必须同时
     约束宽度（maxWidth: .infinity），否则赛道页会横向溢出、显示不全。
  7. 指令链路：状态帧第 2 字节是设备认可的 did，收到后必须同步到后续命令帧；
     写入方式要能在「无响应写 / 带响应写」之间切换；设备页保留协议诊断入口。
     删掉任一条都会退回「能连上、写入回调成功、设备却毫无反应」的状态。
  8. 深色主题与界面约定：强制深色、底部三个标签用各自彩色高亮、选中按钮用
     彩色渐变 + 白字、底部品牌栏用新徽标、赛道模式不再有演示动画。
     启动屏可以是深灰，但不能是纯黑；占位控制器必须有浅色文字用于区分真黑屏。
   9. 文字对比度：所有文字显式着色，禁止裸 `.foregroundStyle(.secondary)` /
     `.tertiary` / `.primary`；提示框用自定义 WingAlertOverlay 而非系统 .alert；
     List 行 / 分组标题 / 两行重发按钮都要有确定颜色，否则深色下「字是空白」。
 10. 一键协议测试矩阵：蓝牙层要枚举全部可写特征值，控制器要能生成用例、
     逐项发送、标记成功、复制报告，设备页要有测试面板入口。删掉任一条，
     都会退回「只能靠猜」的状态。

用法：
    python tools/verify_swift_sources.py           # 检查全部 Swift 文件
"""

from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT_DIR = ROOT / "WingControl"

FIXED = {"width", "height"}
FLEXIBLE = {"minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight"}
KNOWN_FRAME_LABELS = FIXED | FLEXIBLE | {"alignment"}

SUBSTRING_CALLS = re.compile(r"\.(?:prefix|suffix|dropFirst|dropLast|split)\s*\(")
LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")


def mask_strings_and_comments(src: str) -> str:
    """把字符串字面量与注释内容替换为等长空格，保留括号结构与换行。"""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                j += 1
            for k in range(i, min(j, n)):
                if src[k] != "\n":
                    out[k] = " "
            i = j
        elif ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, min(j, n)):
                if src[k] != "\n":
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def find_frame_calls(masked: str):
    """返回 [(行号, 参数原始文本)]，按括号深度匹配 .frame(...) 调用。"""
    for m in re.finditer(r"\.frame\s*\(", masked):
        # WingProtocol.frame(_:deviceID:) 是本项目自己的协议方法，不是 SwiftUI 修饰符
        if re.search(r"\bWingProtocol\s*$", masked[: m.start()]):
            continue
        start = m.end()
        depth, i = 1, start
        while i < len(masked) and depth:
            if masked[i] == "(":
                depth += 1
            elif masked[i] == ")":
                depth -= 1
            i += 1
        yield masked.count("\n", 0, m.start()) + 1, masked[start : i - 1]


def top_level_labels(args: str) -> list[str]:
    """按顶层逗号切分参数，取每段的实参标签。"""
    parts, depth, buf = [], 0, []
    for ch in args:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf).strip())
    labels = []
    for part in parts:
        if not part:
            continue
        m = LABEL.match(part)
        labels.append(m.group(1) if m else "<位置参数>")
    return labels


def interpolation_fragments(src: str) -> list[tuple[int, str]]:
    """提取所有 \\( ... ) 插值片段（含行号），括号可嵌套。"""
    found = []
    i, n = 0, len(src)
    while i < n - 1:
        if src[i] == "\\" and src[i + 1] == "(":
            depth, j = 1, i + 2
            while j < n and depth:
                if src[j] == "(":
                    depth += 1
                elif src[j] == ")":
                    depth -= 1
                j += 1
            found.append((src.count("\n", 0, i) + 1, src[i + 2 : j - 1]))
            i = j
        else:
            i += 1
    return found


def check_file(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8")
    masked = mask_strings_and_comments(src)
    rel = path.relative_to(ROOT).as_posix()
    errors: list[str] = []

    # 1) .frame 重载混用 / 未知参数
    for line, args in find_frame_calls(masked):
        labels = top_level_labels(args)
        used = set(labels) - {"<位置参数>"}
        if (used & FIXED) and (used & FLEXIBLE):
            errors.append(
                f"{rel}:{line}: .frame 混用了固定尺寸与弹性尺寸参数 {sorted(used)}；"
                "SwiftUI 没有这个重载，请统一用 min*/max* 或只用 width/height"
            )
        unknown = used - KNOWN_FRAME_LABELS
        if unknown:
            errors.append(f"{rel}:{line}: .frame 未知参数 {sorted(unknown)}")

    # 2) 字符串插值中的 Substring
    for line, frag in interpolation_fragments(src):
        if SUBSTRING_CALLS.search(frag) and "String(" not in frag:
            errors.append(
                f"{rel}:{line}: 字符串插值里是 Substring，LocalizedStringKey 无法插值；"
                "请用 String(...) 包裹"
            )

    # 3) 可选绑定统一写法
    for line, text in enumerate(src.splitlines(), 1):
        if re.search(r"\bguard\s+let\s+self\s*,", text):
            errors.append(f"{rel}:{line}: 请写成 `guard let self = self`（保持跨工具链一致）")

    # 4) 括号平衡（已屏蔽字符串与注释）
    for open_ch, close_ch in [("{", "}"), ("(", ")"), ("[", "]")]:
        if masked.count(open_ch) != masked.count(close_ch):
            errors.append(
                f"{rel}: 括号不平衡 {open_ch}{close_ch} = "
                f"{masked.count(open_ch)}/{masked.count(close_ch)}"
            )

    # 5) UIViewRepresentable 动画帧原图 710pt 宽，只写 .frame(height:) 会横向撑破卡片
    for m in re.finditer(r"AnimatedImageView\s*\(", masked):
        tail = masked[m.start() : m.start() + 600]
        frame_args = re.search(r"\.frame\s*\(([^)]*)\)", tail)
        if not frame_args or "maxWidth" not in frame_args.group(1):
            line = masked.count("\n", 0, m.start()) + 1
            errors.append(
                f"{rel}:{line}: AnimatedImageView 的 .frame 必须包含 maxWidth: .infinity，"
                "否则大图会把赛道页撑出屏幕"
            )

    if "克拉电动尾翼" in src:
        errors.append(f"{rel}: 仍有旧应用名「克拉电动尾翼」")
    return errors


def check_launch_wiring(swift_files: list[Path]) -> list[str]:
    """校验「一定会创建窗口」的启动链路，防止再次出现启动黑屏。"""
    errors: list[str] = []
    rel_plist = "WingControl/Info.plist"
    plist_path = ROOT / rel_plist
    try:
        info = plistlib.loads(plist_path.read_bytes())
    except Exception as exc:  # noqa: BLE001 - 直接把解析失败报给用户
        return [f"{rel_plist}: 无法解析（{exc}）"]

    manifest = info.get("UIApplicationSceneManifest") or {}
    configs = manifest.get("UISceneConfigurations") or {}
    scenes = configs.get("UIWindowSceneSessionRoleApplication") or []
    delegates = [
        item.get("UISceneDelegateClassName")
        for item in scenes
        if isinstance(item, dict)
    ]
    if "WingControl.SceneDelegate" not in delegates:
        errors.append(
            f"{rel_plist}: UISceneConfigurations 缺少 WingControl.SceneDelegate；"
            "系统只会创建场景不创建窗口，启动后停在黑屏"
        )
    if "UILaunchScreen" not in info:
        errors.append(f"{rel_plist}: 缺少 UILaunchScreen")
    if info.get("UIUserInterfaceStyle") != "Dark":
        errors.append(
            f"{rel_plist}: 缺少 UIUserInterfaceStyle=Dark，"
            "UIKit 启动阶段会跟随系统浅色外观，和全黑主题不一致"
        )
    if info.get("CFBundleIconName") != "AppIcon":
        errors.append(
            f"{rel_plist}: 缺少 CFBundleIconName=AppIcon；GENERATE_INFOPLIST_FILE=NO "
            "时 Xcode 不会自动注入，桌面图标会显示空白"
        )

    pbxproj_path = ROOT / "WingControl.xcodeproj" / "project.pbxproj"
    try:
        pbx = pbxproj_path.read_text(encoding="utf-8")
    except OSError as exc:  # noqa: BLE001
        errors.append(f"project.pbxproj: 读取失败（{exc}）")
    else:
        if "Assets.xcassets in Resources" not in pbx:
            errors.append(
                "project.pbxproj: Assets.xcassets 未加入 Resources 构建阶段，"
                "不会生成 Assets.car，图标与全部界面图片都会丢失"
            )
        if "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" not in pbx:
            errors.append("project.pbxproj: 缺少 ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon")

    colorset = (
        ROOT / "WingControl" / "Assets.xcassets"
        / "LaunchBackground.colorset" / "Contents.json"
    )
    try:
        data = json.loads(colorset.read_text(encoding="utf-8"))
        comp = data["colors"][0]["color"]["components"]
        luminance = (
            0.2126 * float(comp["r"])
            + 0.7152 * float(comp["g"])
            + 0.0722 * float(comp["b"])
        )
        # 深色主题下启动屏用 #1C1C1E 深灰即可；只要不是纯黑，
        # 配合占位控制器的浅色文字就能和「真黑屏」区分开。
        if luminance < 0.04:
            errors.append(
                "LaunchBackground.colorset: 启动屏是纯黑（亮度 "
                f"{luminance:.2f}），与启动失败时的黑屏无法区分；"
                "请使用深灰底并在占位控制器里显示浅色文字"
            )
    except Exception as exc:  # noqa: BLE001
        errors.append(f"LaunchBackground.colorset: 校验失败（{exc}）")

    entry = ROOT / "WingControl" / "App" / "WingControlApp.swift"
    try:
        entry_src = entry.read_text(encoding="utf-8")
    except OSError as exc:
        return errors + [f"启动入口读取失败：{exc}"]
    for token in (
        "class SceneDelegate",
        "makeKeyAndVisible",
        "UIHostingController",
        "LaunchPlaceholderController",
        "label.textColor = .white",
    ):
        if token not in entry_src:
            errors.append(f"App/WingControlApp.swift: 启动入口缺少 {token}")

    visible_at = entry_src.find("makeKeyAndVisible")
    model_at = entry_src.find("WingController()")
    if visible_at >= 0 and model_at >= 0 and visible_at > model_at:
        errors.append(
            "App/WingControlApp.swift: 必须先 makeKeyAndVisible 再构造 WingController，"
            "否则视图层异常时窗口根本没上屏，表现为黑屏"
        )

    mains = sum(
        mask_strings_and_comments(path.read_text(encoding="utf-8")).count("@main")
        for path in swift_files
    )
    if mains != 1:
        errors.append(f"Swift 源码里的应用入口有 {mains} 个，必须恰好 1 个")
    return errors


def check_protocol_wiring() -> list[str]:
    """校验 did 同步 / 写入方式 / 诊断入口，防止「指令静默失效」的问题复发。"""
    errors: list[str] = []
    checks = {
        "WingControl/Model/WingProtocol.swift": [
            ("deviceID: bytes[1]", "状态帧第 2 字节必须解析为设备认可的 did"),
            ("static func data(fromHex", "缺少原始帧输入解析（诊断用）"),
            ("bytes[0] == header", "parse 必须校验帧头 BB"),
        ],
        "WingControl/Services/WingController.swift": [
            ("telemetry.deviceID != deviceID", "收到状态帧后必须同步 did，否则设备会忽略命令"),
            ("applyDeviceID(", "缺少 did 更新入口"),
            ("armReplyCheck(", "缺少状态帧未变化的诊断"),
            ("ble.write(frame, withoutResponse:", "命令写入没有使用可切换的写入方式"),
            ("autoSyncDeviceID", "缺少 did 自动同步开关（手动对比测试需要能关闭）"),
        ],
        "WingControl/Services/BLEManager.swift": [
            ("withoutResponse: Bool = true", "默认应使用与微信小程序一致的无响应写"),
            ("writeWithoutResponse", "未处理特征值只支持无响应写的情况"),
            ("WingProtocol.hexString(data)", "写入日志缺少完整帧内容"),
        ],
        "WingControl/Views/DeviceView.swift": [
            ("协议诊断", "设备页缺少协议诊断入口"),
            ("setDeviceID(hex:", "缺少手动指定 did"),
            ("sendRawFrame(", "缺少原始帧发送"),
        ],
    }
    for rel, tokens in checks.items():
        path = ROOT / rel
        if not path.exists():
            errors.append(f"{rel}: 文件缺失")
            continue
        src = path.read_text(encoding="utf-8")
        for token, message in tokens:
            if token not in src:
                errors.append(f"{rel}: {message}（缺少 {token}）")
    return errors


def check_ui_wiring() -> list[str]:
    """校验深色主题 / 彩色选中态 / 新徽标 / 赛道动画已移除。"""
    errors: list[str] = []
    checks = {
        "WingControl/Theme/Theme.swift": [
            ("static let wingBackground", "缺少深色页面背景色"),
            ("static var wingAccentGradient", "缺少选中态彩色渐变"),
            ("static let wingControlTint", "缺少控制标签的彩色"),
            ("static let wingDeviceTint", "缺少设备标签的彩色"),
            ("static let wingInfoTint", "缺少说明标签的彩色"),
        ],
        "WingControl/App/WingControlApp.swift": [
            ("preferredColorScheme(.dark)", "未强制深色，系统语义色会变回浅色"),
            ("WingAppearance.configure()", "未配置分段控件 / 开关的彩色选中态"),
        ],
        "WingControl/Views/RootTabView.swift": [
            ("safeAreaInset(edge: .bottom", "底部标签栏不是自定义彩色栏"),
            ("Tab.allCases", "缺少三个标签的枚举遍历"),
            ("tab.tint", "标签选中时没有使用各自的彩色"),
        ],
        "WingControl/Views/Components.swift": [
            ("Color.wingAccentGradient", "选中按钮没有用彩色渐变，选中的字会看不清"),
        ],
        "WingControl/Views/ControlView.swift": [
            ("WingBrandBadge()", "底部品牌栏没有换成新徽标"),
            ("Color.wingBackground", "控制页背景不是黑色"),
        ],
    }
    for rel, tokens in checks.items():
        path = ROOT / rel
        if not path.exists():
            errors.append(f"{rel}: 文件缺失")
            continue
        src = path.read_text(encoding="utf-8")
        for token, message in tokens:
            if token not in src:
                errors.append(f"{rel}: {message}（缺少 {token}）")

    control_src = (ROOT / "WingControl/Views/ControlView.swift").read_text(encoding="utf-8")
    if 'Image("Logo")' in control_src:
        errors.append("ControlView.swift: 仍在使用旧小程序的黑白 Logo 素材")

    track_src = (ROOT / "WingControl/Views/TrackModeView.swift").read_text(encoding="utf-8")
    for token in ("AnimatedImageView", "TrackStatus", "TrackAnim", "playAnimation"):
        if token in track_src:
            errors.append(f"TrackModeView.swift: 赛道演示动画已移除，不应再出现 {token}")

    html = (ROOT / "Preview/index.html").read_text(encoding="utf-8")
    for token, message in (
        ("--t-control", "预览页缺少三个标签各自的彩色"),
        ('class="logo"', "预览页底部品牌栏没有换成新徽标"),
        ("linear-gradient(90deg,var(--accent)", "预览页选中态没有用彩色渐变"),
    ):
        if token not in html:
            errors.append(f"Preview/index.html: {message}（缺少 {token}）")
    for token in ('class="anim"', 'class="statusimg"'):
        if token in html:
            errors.append(f"Preview/index.html: 赛道演示动画已移除，不应再渲染 {token}")
    return errors


def check_text_contrast() -> list[str]:
    """深色主题下所有文字必须显式着色，不能依赖系统语义色 / 系统弹窗按钮。

    实测故障：系统 UIAlertController 的「确定」按钮、List 分组标题与默认
    按钮文字在强制深色 + scrollContentBackground(.hidden) 后被判成深色，
    表现为「按钮在、字是空白」。
    """
    errors: list[str] = []
    views = ROOT / "WingControl/Views"

    root_path = views / "RootTabView.swift"
    root_code = "\n".join(
        line for line in root_path.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("//")
    )
    if ".alert(item:" in root_code:
        errors.append("RootTabView.swift: 不要用系统 .alert，按钮文字会与深色背景同色")
    for token, message in (
        ("WingAlertOverlay(", "缺少自定义高对比提示弹层"),
        ('Button("确定")', "自定义弹层缺少可见的「确定」按钮"),
    ):
        if token not in root_code:
            errors.append(f"RootTabView.swift: {message}（缺少 {token}）")

    app_src = (ROOT / "WingControl/App/WingControlApp.swift").read_text(encoding="utf-8")
    if "UIView.appearance().tintColor" not in app_src:
        errors.append("App/WingControlApp.swift: 缺少全局 tint 高对比兜底")

    for name in ("DeviceView.swift", "InfoView.swift"):
        src = (views / name).read_text(encoding="utf-8")
        for token, message in (
            (".listRowBackground(Color.wingSurface)", "List 行没有显式深色背景"),
            ("sectionHeader(", "分组标题没有显式着色"),
            (".tint(Color.wingAccent)", "缺少高对比 tint"),
        ):
            if token not in src:
                errors.append(f"{name}: {message}（缺少 {token}）")

    device = (views / "DeviceView.swift").read_text(encoding="utf-8")
    for token in ('Button("重发上一条指令")', 'Button("切换写入方式并重发")'):
        idx = device.find(token)
        if idx < 0:
            errors.append(f"DeviceView.swift: 缺少 {token}")
        elif ".foregroundStyle(Color.wingAccent)" not in device[idx:idx + 300]:
            errors.append(f"DeviceView.swift: {token} 之后没有显式文字颜色")

    all_swift = "\n".join(
        p.read_text(encoding="utf-8")
        for p in (ROOT / "WingControl").rglob("*.swift")
    )
    for bad in (
        ".foregroundStyle(.secondary)",
        ".foregroundStyle(.tertiary)",
        ".foregroundStyle(.primary)",
    ):
        if bad in all_swift:
            errors.append(
                f"工程内仍有裸系统语义色 {bad}，请换成 "
                "Color.wingTextSecondary / Color.white"
            )

    return errors


def check_test_runner_wiring() -> list[str]:
    """校验一键协议测试矩阵，避免排障能力在后续改动里被误删。"""
    errors: list[str] = []
    checks = {
        "WingControl/Services/BLEManager.swift": [
            ("struct BLEWriteTarget", "缺少可写特征值描述，测试无法枚举写入通道"),
            ("var writeTargets", "缺少可写特征值清单"),
            ("var allCharacteristicInfo", "缺少完整特征值清单（截图排查用）"),
            ("targetUUID: String? = nil", "写入方法不支持按 UUID 指定通道"),
            ("func writeToAll", "缺少群发全部通道的能力"),
            ("func resubscribeNotify", "缺少重新订阅 notify 的测试用例支撑"),
            ("for service in targets", "只扫描第一个主服务会漏掉透传服务"),
        ],
        "WingControl/Services/WingController.swift": [
            ("func buildTestCases(mode:", "缺少测试矩阵生成"),
            ("func sendTestFrames(", "缺少测试专用发送通道"),
            ("final class WingTestRunner", "缺少测试运行器"),
            ("func markSuccess()", "缺少用户标记成功编号"),
            ("func copyReport()", "缺少复制测试报告"),
            ("for value in 0...255", "缺少 0x00~0xFF did 全扫描"),
            ("testRunner.attach(self)", "测试运行器没有挂到控制器"),
            ("telemetryRevision += 1", "缺少状态帧计数，自动判定会失效"),
        ],
        "WingControl/Views/DeviceView.swift": [
            ("一键协议测试", "设备页缺少一键测试入口"),
            ("WingTestPanel(runner:", "测试面板没有挂载"),
            ("runner.start(mode: .standard)", "缺少开始标准矩阵按钮"),
            ("runner.start(mode: .didScan)", "缺少 did 全扫描按钮"),
            ("runner.markSuccess()", "面板缺少标记成功按钮"),
            ("runner.copyReport()", "面板缺少复制报告按钮"),
            ("Text(\"#\\(runner.currentIndex)\")", "面板缺少大号编号显示"),
        ],
    }
    for rel, tokens in checks.items():
        path = ROOT / rel
        if not path.exists():
            errors.append(f"{rel}: 文件缺失")
            continue
        src = path.read_text(encoding="utf-8")
        for token, message in tokens:
            if token not in src:
                errors.append(f"{rel}: {message}（缺少 {token}）")
    return errors


def main() -> int:
    files = sorted(SWIFT_DIR.rglob("*.swift"))
    if not files:
        print(f"ERROR: 找不到 Swift 文件：{SWIFT_DIR}")
        return 1

    errors: list[str] = []
    frames = 0
    for path in files:
        errors.extend(check_file(path))
        frames += len(list(find_frame_calls(mask_strings_and_comments(path.read_text(encoding="utf-8")))))
    errors.extend(check_launch_wiring(files))
    errors.extend(check_protocol_wiring())
    errors.extend(check_ui_wiring())
    errors.extend(check_text_contrast())
    errors.extend(check_test_runner_wiring())

    print(f"检查 {len(files)} 个 Swift 文件、{frames} 处 .frame 调用、启动 / 指令 / 界面 / 文字对比度 / 测试矩阵配置")
    if errors:
        print("\n=== 发现 %d 个问题 ===" % len(errors))
        for err in errors:
            print("ERROR:", err)
        return 1
    print("静态预检通过（frame 重载 / Substring 插值 / 可选绑定 / 括号 / 名称 / 启动链路 / 动画尺寸 / 指令链路 / 深色界面 / 文字对比度 / 测试矩阵）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
