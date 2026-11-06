# 尾翼控制器 · iOS 原生版

把已下架的微信小程序 `__APP__.wxapkg` 完整逆向后重做的 **SwiftUI + CoreBluetooth** 原生 iOS 应用。

- 保留了原小程序全部业务功能与文案，通信协议逐字节一致；
- 界面按 Apple HIG 重新组织（3 个 Tab、语义化颜色、Dynamic Type、VoiceOver、触觉反馈）；
- 原始图片素材已合成到深色画布并放入 `Assets.xcassets`，GIF 拆成逐帧动画；
- 附带一个**无需 Mac、无需硬件**的交互原型 `Preview/index.html`，在 Windows 上双击即可点。

> 本机是 Windows，无法直接编译 iOS 应用：工程已配好 **GitHub Actions**，推送仓库即可在 macOS runner 上自动打出 IPA（见第 2 节）；也可在 macOS + Xcode 15+ 本地打开。交互原型与协议校验脚本可在本机直接运行。

---

## 1. 快速开始

| 项目 | 要求 |
| --- | --- |
| 应用名称 | **尾翼控制器**（`Info.plist` 的 `CFBundleDisplayName` / `CFBundleName`） |
| 工程 | `WingControl.xcodeproj`（双击打开） |
| 工具 | macOS + Xcode 15 或更高 |
| 系统 | iOS 16.0+（iPhone / iPad） |
| 语言 | Swift 5，SwiftUI，无第三方依赖（无需 CocoaPods / SPM） |
| 签名 | 首次真机运行需在 Target → Signing & Capabilities 选择自己的 Team；模拟器运行无需签名 |
| 权限 | `NSBluetoothAlwaysUsageDescription` 已写入 Info.plist |
| 云端打包 | `.github/workflows/build-ipa.yml`，无需 Mac 即可产出 IPA（见第 2 节） |

**打开后先做什么**：iOS 模拟器没有蓝牙，App 会自动进入「演示模式」；真机上请到「设备」Tab 点「搜索设备」——这是**唯一触发蓝牙权限弹窗的时机**（不在启动时申请）。

---

## 2. GitHub Actions 自动打包 IPA

把 **`WingControl-iOS/` 整个目录作为仓库根目录** 推送到 GitHub（`.github/` 必须在仓库根），工作流 `.github/workflows/build-ipa.yml` 就会生效。

### 触发方式

| 事件 | 结果 |
| --- | --- |
| push 到 `main` / `master`、Pull Request | 构建并上传 IPA 到 Actions 工件 |
| Actions → 「构建 IPA」→ Run workflow | 可手动选 `runner`、`sign_mode`、`export_method` |
| push `v*` 标签（如 `v1.0.0`） | 额外创建 GitHub Release 并附上 IPA |

默认 `sign_mode = auto`：**不配置任何 Secrets 也能跑**，产出免签名 IPA，不需要 Apple 开发者账号；4 个 Secrets 配齐后自动升级为签名 IPA。

### Runner 镜像

工作流默认固定在 **`macos-15`**（arm64，Xcode 16.x）。GitHub 的 `macos-14` 镜像已于 **2026-11-02 退役**，继续用会直接报 `The configuration 'macos-14-arm64-us-default' is not supported`，job 连机器都分配不到——这与工程代码无关。

手动运行时可在 `runner` 下拉框切换：

| 选项 | 说明 |
| --- | --- |
| `macos-15`（默认） | arm64，Xcode 16.x，版本跨度最小 |
| `macos-latest` | 目前指向 macOS 26，Xcode 跨度较大 |
| `macos-15-intel` | x86_64，仅在确实需要 Intel 环境时选 |

push / PR / tag 触发的构建固定用 `macos-15`；若将来该标签也退役，改 `build-ipa.yml` 中 `runs-on` 的默认值即可。私有仓库会按 macOS 分钟额度计费（倍率高于 Linux）。

### 两种产物

| 文件 | 用途 |
| --- | --- |
| `WingControl-unsigned.ipa` | 免签名。用 AltStore / Sideloadly / TrollStore 侧载；普通未越狱 iPhone 无法直接安装 |
| `WingControl-signed.ipa` | 按描述文件签名。`ad-hoc` 可直接装到 profile 已登记 UDID 的设备，`app-store` 用于上传 App Store Connect |

在 Actions 运行页底部 `Artifacts` 下载（保留 30 天）；打 tag 时还会附到 Release。归档后脚本会校验 `CFBundleDisplayName == 尾翼控制器`，避免打出旧名称的包。

### 配置签名（可选，不配也能用）

仓库 → Settings → Secrets and variables → Actions → New repository secret：

| Secret | 内容 |
| --- | --- |
| `IOS_P12_BASE64` | 证书 + 私钥导出为 `.p12` 后的 base64 单行文本 |
| `IOS_P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `IOS_MOBILEPROVISION_BASE64` | `.mobileprovision` 的 base64 文本 |
| `IOS_TEAM_ID` | Apple Developer Team ID（如 `A1B2C3D4E5`） |

在 Mac 上准备：`钥匙串访问` 中选中证书及其私钥 → 右键「导出」存为 `cert.p12` 并设置密码；描述文件从 Apple Developer 下载。

```bash
base64 -i cert.p12 | pbcopy                       # 粘贴为 IOS_P12_BASE64
base64 -i WingControl.mobileprovision | pbcopy   # 粘贴为 IOS_MOBILEPROVISION_BASE64
```

Windows 上可用 `certutil -encode cert.p12 cert.b64`，再去掉首尾的 `-----BEGIN/END CERTIFICATE-----` 行并拼成单行。

> Bundle ID 固定为 `com.kela.WingControl`，描述文件的 App ID 需与之匹配（通配符 App ID 也可以）。
> 手动运行时的 `export_method` 可选 `ad-hoc`（默认）/ `development` / `app-store` / `enterprise`。

工作流不依赖任何第三方 Action，只用官方 `actions/checkout`、`actions/upload-artifact` 与 runner 自带的 `gh`；证书只写入 `RUNNER_TEMP` 下的临时钥匙串，任务结束即销毁。

构建日志 `build/xcodebuild-archive.log` / `xcodebuild-export.log` 会实时打印到 Actions 日志；**任一环节失败时**还会作为 `build-log-<run number>` 工件上传，首次编译排错可直接下载。

### 本地构建（macOS）

```bash
cd WingControl-iOS
bash tools/build-ipa.sh                # 免签名 → build/ipa/WingControl-unsigned.ipa
bash tools/build-ipa.sh --signed       # 需先设置 IOS_TEAM_ID / IOS_PROFILE_UUID
```

> **维护约定**：workflow 与脚本中的 shell 变量一律写成 `${VAR}`，且工作流显式设置 `LANG/LC_ALL=en_US.UTF-8`。macOS 自带的 bash 3.2 在 `set -u` 下会把变量名后紧跟的中文标点字节吞进变量名，写成 `$VAR；` 会报 `unbound variable`；花括号能彻底划定边界。

---

## 3. 目录结构

```
WingControl-iOS/                              # ← 作为 GitHub 仓库根目录
├── .github/workflows/build-ipa.yml           # GitHub Actions 自动归档并导出 IPA
├── .gitignore                                # 忽略 build/ 与签名材料
├── WingControl.xcodeproj/
│   ├── project.pbxproj                       # 手工生成的完整 Xcode 工程
│   ├── project.xcworkspace/
│   └── xcshareddata/xcschemes/WingControl.xcscheme   # 共享 Scheme，CI 必需
├── WingControl/
│   ├── Info.plist                            # 应用名称、蓝牙权限、启动屏、方向
│   ├── Assets.xcassets/                      # 25 个 imageset + AppIcon + 2 个 colorset
│   ├── App/WingControlApp.swift              # @main 入口
│   ├── Model/
│   │   ├── WingProtocol.swift                # 指令帧编解码、速度校验、档位映射
│   │   └── WingUIState.swift                 # 页面状态、弹窗、日志模型
│   ├── Services/
│   │   ├── BLEManager.swift                  # CBCentralManager / CBPeripheral 封装
│   │   ├── WingController.swift              # 状态机、动作分发、回复解析、演示模式
│   │   └── Haptics.swift                     # 触觉反馈
│   ├── Theme/Theme.swift                     # 颜色与 8pt 间距
│   └── Views/
│       ├── RootTabView.swift                 # TabView + 弹层 + 全局提示
│       ├── ControlView.swift                 # 主控制页 + 底部点火按钮
│       ├── DailyModeView.swift               # 日常模式：档位 / 一键 / AUTO
│       ├── TrackModeView.swift               # 赛道模式：动画 / 刹车灵敏度
│       ├── DeviceView.swift                  # 扫描、连接、调试、命令日志
│       ├── InfoView.swift                    # 说明、协议、启动日志
│       └── Components.swift                  # 通用组件 + 双列滚轮 + 逐帧动画
├── Preview/index.html                        # 单文件交互原型（图片已内嵌 base64）
└── tools/
    ├── build-ipa.sh                          # archive + 导出 IPA（CI 与本地共用）
    └── verify_protocol.py                    # 协议一致性自检脚本
```

---

## 4. 功能对照

| 原小程序 | iOS 版 | 说明 |
| --- | --- | --- |
| 首页顶部「日常模式 / 赛道模式」 | 控制页 Segmented Control | 2 个模式用分段控件，3 个主功能用 TabBar（符合 HIG） |
| 尾翼图片 + 竖向档位条 5/4/3 + 升/降 | 控制页深色画布 | 档位实际只有 **0 / 3 / 4 / 5** 四档（包内只有 tial0/3/4/5.png） |
| 一键上升 / 一键下降 | 同 | `8006 01/02 00` |
| AUTO 开关 + 双列 picker-view | 开关 + `UIPickerView` 双列滚轮 | 单次回调同时读取两列，与 `bindChangeleft` 一致；非法组合自动回弹 |
| 四条速度校验规则 | 完全相同 | 见第 5 节 |
| 两列同时为 0 → 校准确认框 | 相同 + 显式「进入校准模式」入口 | 原逻辑逐列滚动很难到达 (0,0)，补一个入口保证功能可用 |
| 赛道强 / 中 / 弱 | 同 | 强度显示 `a = -2 / -3 / -5 m/s²` |
| 赛道说明弹层 | sheet + 下滑关闭 + 显式关闭按钮 | 原说明文案完整保留 |
| 点火升降 | 同 | 以设备回复判定成功 / 失败，分别弹结果页 |
| 设备搜索底部弹层 | 独立「设备」Tab | 更清晰，且可查看连接状态与日志 |
| 启动日志页 | 「说明」Tab 内的启动记录 | 使用 UserDefaults 持久化 |
| 跳转其它小程序商城 | **移除** | iOS 无法跳转微信小程序，且原商城已随小程序下架 |
| 5 秒启动 GIF 动画 | 改为系统启动屏 | 避免全屏等待，符合 HIG |

---

## 5. 协议还原（与 Swift 代码逐字节对应）

指令帧固定 6 字节：`BB | did | 80 | cmd | p1 | p2`

- `did`：App 首次启动随机生成 0~255 并持久化（对应小程序 `wx.setStorage({key:"did"})`）。
- 所有速度值以十六进制单字节发送，例如 80 km/h → `0x50`。

| 功能 | 帧 |
| --- | --- |
| 设置档位 | `BB did 80 01 step 00` |
| 自动升降 | `BB did 80 02 down up` |
| 关闭自动 | `BB did 80 03 00 00` |
| 赛道灵敏度（强/中/弱 = 1/2/3） | `BB did 80 04 type 00` |
| 点火升降（关/开 = 0/1） | `BB did 80 05 on 00` |
| 一键上升 / 下降 | `BB did 80 06 01/02 00` |

**设备 notify 上报**：至少 8 字节基础帧，字节 3~7 依次为 `auto 标志 / 档位 / 车速 / 降速临界 / 升速临界`；12 字节扩展帧再追加 `赛道类型 / 点火开关 / 点火就绪 / 点火结果`。`auto == 2` 表示自动模式已开启。

**速度校验顺序**（左列降速 `down`、右列升速 `up`）：

1. `down == 0 && up == 0` → 弹确认框，进入校准模式；
2. `up < down + 20` → 「降速加速临界范围总大于20码」；
3. `down == 0 && up != 0` → 「下降速度必须大于零，升降都为零校准除外」；
4. `up <= down` → 「升起速度必须大于下降速度，升降都为零校准除外」。

**蓝牙设备**：扫描只接受名称以 `JDY` 开头的 BLE 模块；连接后发现主服务，优先选择同时支持 `write` 与 `notify` 的特征值（JDY 常见 `FFE0/FFE1`），否则退化为分别取可写 / 可通知特征值。写入时按特征值属性自动选 `.withResponse` 或 `.withoutResponse`。

运行 `python tools/verify_protocol.py` 可校验全部帧、校验规则和回复解析。

---

## 6. iOS 实现要点

- **权限时机**：`CBCentralManager` 延迟创建，只在用户点击「搜索设备 / 连接」时申请蓝牙权限；`CBCentralManager.state == .unknown` 时用 `pendingAction` 等 `.poweredOn` 后再继续，避免首次点击误报失败。
- **断线处理**：`didDisconnectPeripheral` 重置特征值并提示，可在「设备」页点「连接上次使用的设备」重连（缓存 peripheral UUID）。
- **演示模式**：无硬件 / 模拟器下模拟设备回复帧，可完整走通档位、AUTO、赛道、点火成功与失败流程；「模拟已装车内实体按键」开关用于复现点火失败分支。
- **无障碍**：所有交互元素带 `accessibilityLabel` / `accessibilityValue` / `accessibilityHint`；触控目标 ≥ 44pt；状态同时用图标 + 文字，不只用颜色。
- **外观**：外层使用语义化颜色自动适配浅色 / 深色模式，控制画布固定深色以还原原素材；自定义字体走 `UIFont.preferredFont`，支持 Dynamic Type。
- **动效**：GIF 拆帧用 `UIImageView.animationImages` 播放，遵循「减弱动态效果」时自动静止；不使用全屏 spinner。
- **触觉**：档位、模式、校验失败、点火成功分别使用 selection / impact / notification 反馈。

---

## 7. 已知限制

1. 未做后台蓝牙与 State Restoration，App 退到后台后不保证持续连接。
2. 原小程序的商城跳转、微信登录、`navigateToMiniProgram` 在 iOS 无对应能力，已移除。
3. 原包中 `weiyistart.gif`、`logo.gif` 的长启动动画未移植，改为系统启动屏；`track_top.gif` / `fire.gif` 已拆帧保留。
4. 尚未在真机 + 真实 JDY 模块上联调。若你的模块服务 UUID 不是 `FFE0/FFE1`，当前「动态发现主服务」逻辑仍可工作；若特征值属性与假设不符，请把 `BLEManager.swift` 中的筛选条件按实际模块调整。
5. 工程由脚本生成并在 Windows 上完成静态校验，**本地未在 Xcode 中编译过**；GitHub Actions 首次运行日志即为最终编译验证。首次打开若 Xcode 提示升级设置，按提示确认即可。

---

## 8. 素材说明

`Assets.xcassets` 中的图片全部来自用户提供的原始小程序包（半透明 PNG 已合成到 `#0F0F0F` 深色底以适配控制画布），AppIcon 由原 `logo.png` 重新排版生成。素材版权归原小程序权利人所有，本工程仅用于功能迁移。
