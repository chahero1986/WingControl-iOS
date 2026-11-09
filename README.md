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

在 Actions 运行页底部 `Artifacts` 下载（保留 30 天）；打 tag 时还会附到 Release。归档后脚本会校验 `CFBundleDisplayName == 尾翼控制器`、`CFBundleIconName == AppIcon`、`UISceneDelegateClassName` 以及 `Assets.car` 是否存在，避免打出旧名称、丢图标或启动黑屏的包。

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

### 提交前本地预检（Windows 也能跑）

本机没有 Swift 编译器，SwiftUI API 误用只有推到 CI 才会暴露。提交前先跑：

```bash
python tools/verify_swift_sources.py     # Swift 源码静态检查
python tools/verify_protocol.py          # 协议帧与校验规则
```

`verify_swift_sources.py` 检查 `.frame` 重载是否混用、字符串插值里的 `Substring`、可选绑定写法、括号平衡、旧应用名，以及**启动链路完整性**（场景清单指向 `SceneDelegate`、全工程恰好一个入口、启动屏不是纯黑且占位控制器有浅色文字、图标键与深色外观）、**指令链路完整性**（状态帧 did 同步、写入方式可切换、设备页诊断入口）和**界面链路**（深色主题、彩色底部栏与选中态、新徽标、赛道动画已移除）；同一检查也已接入工作流，在 `xcodebuild` 之前运行。

首次真实编译（Xcode 16.4 / macOS 15 runner）报过 `DailyModeView.swift:42: extra argument 'minHeight' in call`：SwiftUI 的 `frame` 有两个重载——`frame(width:height:alignment:)` 与 `frame(minWidth:…:maxHeight:alignment:)`——`width`/`height` 不能和 `min*`/`max*` 同用。现在统一改为 `.frame(minWidth: 44, minHeight: 44)`，既合法又能随 Dynamic Type 放大。

> **维护约定**
> 1. 触控目标一律用 `minWidth`/`minHeight`，不要写 `width` + `minHeight`（静态预检会拦截）；
> 2. 字符串插值里出现 `Substring` 要用 `String(...)` 包一层，`LocalizedStringKey` 没有对应插值重载；
> 3. workflow 与脚本中的 shell 变量一律写成 `${VAR}`，且工作流显式设置 `LANG/LC_ALL=en_US.UTF-8`。macOS 自带的 bash 3.2 在 `set -u` 下会把变量名后紧跟的中文标点字节吞进变量名，写成 `$VAR；` 会报 `unbound variable`；花括号能彻底划定边界。
> 4. 仓库根的 `.gitattributes` 强制所有文本文件用 LF 存储；Windows 编辑后不要提交 CRLF，macOS 的 bash 3.2 会把 `\r` 当成命令内容的一部分；
> 5. 不要删 `Info.plist` 的 `UISceneConfigurations`，也不要把应用入口改回 SwiftUI 隐式生命周期——工程是手工生成的，没有 Xcode 自动生成的场景清单，改回去会黑屏（静态预检会拦截）；
> 6. `AnimatedImageView` 是 `UIViewRepresentable`，不要只写 `.frame(height:)`，必须同时约束宽度（`maxWidth: .infinity`）：动画帧原图 710pt 宽，否则赛道页会横向溢出、显示不全（静态预检会拦截）；
> 7. 不要在 `handleReply` 里删掉 did 同步、不要把写入方式写死成 `.withResponse`、不要移除设备页「协议诊断」——真机上会退回「能连上、写入回调成功、设备毫无反应」，且这种故障在 ATT 层看不到任何报错（静态预检会拦截）；
> 8. 手写 `Info.plist` 必须保留 `CFBundleIconName = AppIcon`，`SceneDelegate` 必须「先 `makeKeyAndVisible()` 再构造 `WingController` / SwiftUI 根视图」。删掉前者桌面图标空白，顺序反过来则窗口可能根本不上屏而黑屏（静态预检与打包脚本都会拦截）。
> 9. 界面固定深色：不要删 `UIUserInterfaceStyle=Dark` 与 `.preferredColorScheme(.dark)`，不要把底部栏改回系统 `TabView`、不要把选中按钮改回纯 `.accentColor`、不要恢复赛道演示动画或旧 `Image("Logo")`——这些都会让「选中看不见 / 背景不协调」复发（静态预检会拦截）。

### 启动黑屏的修复说明

现象：装到真机 / 模拟器后一直停在全黑画面，没有报错也没有崩溃日志。

根因有两层：

1. 工程 `GENERATE_INFOPLIST_FILE = NO`，`Info.plist` 手写；原来 `UIApplicationSceneManifest` 只有 `UIApplicationSupportsMultipleScenes`，**缺少 `UISceneConfigurations`**。系统据此认为 App 走场景生命周期，却找不到场景代理，于是创建了 `UIWindowScene` 但没有创建 `UIWindow`，SwiftUI 的 `WindowGroup` 也就无处渲染。
2. 启动屏 `LaunchBackground` 原本是小程序同款 `#0F0F0F` 深色，与「无窗口」叠在一起，视觉上就是纯黑。

修复：

| 文件 | 改动 |
| --- | --- |
| `WingControl/App/WingControlApp.swift` | 改为 `@main AppDelegate` + `SceneDelegate`；`SceneDelegate` 显式创建 `UIWindow`、设置浅色底并装载 `UIHostingController(rootView: WingRootView)`；`NSLog` 打印启动与窗口装载，便于查日志 |
| `WingControl/Info.plist` | 补全 `UISceneConfigurations` → `UIWindowSceneSessionRoleApplication` → `UISceneDelegateClassName = WingControl.SceneDelegate` |
| `LaunchBackground.colorset` | 由 `#0F0F0F` 改为浅色 `#F2F2F7`，启动阶段不再像黑屏 |
| `Preview/index.html` | 手机屏加「界面加载中」占位与 `window.onerror` 兜底，JS 出错时直接显示错误而不是纯黑 |
| `tools/verify_swift_sources.py` | 新增启动链路检查，防止后续改动把黑屏问题带回来 |

> 界面仍全是 SwiftUI；只是把「谁来建窗口」这件事从系统隐式推断改成代码显式创建。真机上若仍异常，可用 Xcode 的 Devices & Simulators / Console 过滤 `WingControl` 看是否打印 `application didFinishLaunching` 与 `window installed`：前者没有 = 启动前就失败（签名 / bundle 配置），只有前者没有后者 = 场景未连接，`RootTabView` 报错 = 视图层问题。

### 桌面图标丢失与安装后黑屏复发

现象：重新打包安装后，桌面显示空白 / 默认图标，打开又停在黑屏。

**图标**：工程 `GENERATE_INFOPLIST_FILE = NO`，`Info.plist` 是手写的，Xcode 不会像新模板那样自动注入 `CFBundleIconName`。`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 只负责把 `AppIcon.appiconset` 编译进 `Assets.car`；运行时系统靠 plist 里的 `CFBundleIconName` 去查名字，缺了它，图标资源再合规也用不上。`AppIcon.png` 本身是 1024×1024、RGB 无 alpha，无需改图。

**黑屏**：`SceneDelegate` 原来是「先构造 `WingController` 与 SwiftUI 根视图 → 最后 `makeKeyAndVisible()`」。中间任一环节异常，窗口就没建立，用户看到的是启动屏而不是界面。

| 位置 | 修复 |
| --- | --- |
| `WingControl/Info.plist` | 补 `CFBundleIconName = AppIcon` |
| `WingControl/App/WingControlApp.swift` | `SceneDelegate` 先创建 `UIWindow`、设 `.systemBackground`、装浅色占位控制器并 `makeKeyAndVisible()`，再加载状态机与 SwiftUI 根视图；占位用原生 Auto Layout + Dynamic Type 文字（工程保持零第三方依赖，不引入 SnapKit），四个阶段都有 `NSLog` |
| `tools/build-ipa.sh` | 归档后校验 `CFBundleIconName == AppIcon`、`Assets.car` 存在；最终 IPA 再校验 `Payload/WingControl.app/Assets.car`，任一缺失直接拒绝出包 |
| `.github/workflows/build-ipa.yml` | Actions 日志打印 Icon Name 与 Assets.car 大小 |
| `tools/verify_swift_sources.py` | 启动链路检查新增 `CFBundleIconName`、Resources 构建阶段、`ASSETCATALOG_COMPILER_APPICON_NAME`，以及「窗口先上屏」顺序 |

真机自检：Xcode → Devices & Simulators / Console 过滤 `WingControl`，正常启动依次打印：

`1/4 application didFinishLaunching` → `2/4 configurationForConnecting` → `3/4 window installed with placeholder` → `4/4 SwiftUI root view attached`

- 只有 1/4：场景配置没生效，检查 `UISceneConfigurations` 与 Product Module Name；
- 到 3/4 没有 4/4：状态机 / SwiftUI 根视图异常，此时屏幕应显示浅色「尾翼控制器」占位而不是全黑；
- 一条都没有：包本身不对（装到了旧 IPA，或签名 / bundle 结构损坏）。

> 侧载提示：免签名 IPA 经 AltStore / Sideloadly 重签时，若工具重新生成了 `Info.plist`，可能再次丢掉 `CFBundleIconName`。装完先看桌面图标、再打开 App 看能否进「设备」页；若图标没了但界面正常，优先换用签名 IPA 或更新侧载工具。

### 赛道模式页面显示不全的修复

赛道动画是 `UIViewRepresentable` 包装的 `UIImageView`，帧原图 **710×400**；原代码只写 `.frame(height: 150)`，宽度没有约束，视图按 710pt 固有宽度撑开卡片，右半边被挤出屏幕。

| 位置 | 修复 |
| --- | --- |
| `Views/Components.swift` → `AnimatedImageView` | 先设静态首帧让固有尺寸有效，降低水平/垂直内容吸附与压缩优先级，让父容器决定尺寸；抽出 `apply(_:to:)` 统一播放/暂停/减弱动态效果，避免每次 SwiftUI 刷新都重新装载图片 |
| `Views/Components.swift` → `DarkCanvas` | 内容统一加 `.frame(maxWidth: .infinity)`，通用防横向溢出 |
| `Views/TrackModeView.swift` | 动画视图改为 `.frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)` + `.clipped()`；状态图、说明区、按钮行都明确宽度；说明按钮 `.fixedSize` 防被压扁 |
| `Views/ControlView.swift` | 滚动内容 VStack 加 `.frame(maxWidth: .infinity, alignment: .top)` |
| `Views/RootTabView.swift` | 点火成功弹层里的同类动画同样约束；赛道/AUTO 说明弹层默认展开到 `.large` 并显示拖拽指示条，长文本不用先手动上拉 |
| `Preview/index.html` | 屏幕区禁横向溢出、底部留白；矮窗口（≤920px 高）时手机模型收进视口，内容在屏幕区内滚动，底部不再被截断 |
| `tools/verify_swift_sources.py` | 新增检查：所有 `AnimatedImageView` 的 `.frame` 必须含 `maxWidth` |

### 指令发送后设备毫无反应的修复

真机现象（JDY-10M-2.3）：连接成功、`Service FFE0 · Write FFE1 · Notify FFE1`、`notify 启动成功`、设备每秒上报状态帧、`写入特征值 FFE1`、`发送命令成功` 全部正常，但尾翼不动，状态帧始终不变。

日志里两条关键信息：

| 来源 | 帧 | 第 2 字节 |
| --- | --- | --- |
| 设备状态帧 | `BB 1C 20 01 05 00 00 A5 …` | `1C` |
| App 发出的命令 | `BB 0B 80 01 03 00` | `0B` |

`did` 是**设备认可的主机 ID**：原微信小程序首次启动随机生成一次并永久存进 `wx.setStorage({key:"did"})`，设备记住了这个值（本例 `1C`），之后只接受带该 did 的命令。iOS App 首次启动又随机生成 `0B`，虽然 6 字节帧结构、特征值、ATT 写入都正确，设备仍静默丢弃命令——这也解释了为什么 `didWriteValueFor` 回调成功、状态帧却毫无变化。

| 位置 | 修复 |
| --- | --- |
| `Model/WingProtocol.swift` | `WingTelemetry` 增加 `deviceID`，`parse` 校验帧头并解析状态帧第 2 字节；新增 `data(fromHex:)` 供诊断发送原始帧 |
| `Services/WingController.swift` | 收到状态帧时若设备 did 与本机不同，自动同步并持久化，后续命令都用设备认可的值；新增「指令发出后 3.5 秒状态帧未变化」诊断日志，以及 `setDeviceID` / `sendRawFrame` / `resendLastFrame` |
| `Services/BLEManager.swift` | 写入方式改为可切换，默认**无响应写**（与微信小程序在 iOS 上的行为一致），按特征值属性自动回退；日志打印完整帧、写入方式与特征值 UUID |
| `Views/DeviceView.swift` | 新增「协议诊断」区：显示本机 did / 设备回传 did / 写入方式 / 上一条指令，支持手动指定 did、直接发送原始 hex 帧、重发、切换写入方式重发 |
| `tools/verify_protocol.py` / `verify_swift_sources.py` | 新增 did 同步与测试帧解析用例；静态预检增加「指令链路」检查 |

排查顺序（都在「设备」Tab）：

1. 连接后看「协议诊断」里的**设备回传 ID**，App 会自动同步，日志出现 `指令 ID：0B → 1C（按设备状态帧同步）`。
2. 再发一次档位指令。状态帧变化即成功，日志会打印 `设备已响应：状态帧发生变化`。
3. 若仍不变，切换「无响应写」并点「切换写入方式并重发」，两种 ATT 写法各试一次。
4. 仍无效时，用「直接发送原始帧」手动发 `BB1C80010300`（把 `1C` 换成日志里设备回传的值），或手动指定 did 后重发。
5. 全程看「最近命令日志」：命令帧、写入方式、状态帧都会记录。出现 `注意：指令发出后状态帧没有变化` 说明设备确实忽略了命令，而不是界面没刷新。

> 自动同步 did 是零风险的：若状态帧第 2 字节只是设备地址、设备并不校验 did，改成该值也不影响执行；若设备是「记住已配对主机」或「每次连接下发挑战值」，同步则正好对齐。

### 深色主题与界面调整（2026-11-09）

按真机使用反馈做的 5 项纯 UI 调整，**不涉及蓝牙协议与指令逻辑**：

| 需求 | 实现 |
| --- | --- |
| 背景改黑、整体协调 | `Info.plist` 加 `UIUserInterfaceStyle=Dark`，`WingRootView` 加 `.preferredColorScheme(.dark)`；`Theme.swift` 统一 `wingBackground=#0F0F0F` / `wingSurface=#1C1C1E` / `wingTabBar`，控制画布沿用原素材合成底色并以边框分层；启动屏改深灰，占位控制器深灰底 + 白字「尾翼控制器 / 正在启动…」，仍能与真黑屏区分 |
| 底部三个标签选中后图标看不见 | 弃用系统 `TabView` 的 tint，改为 `safeAreaInset` 挂载的自定义彩色底部栏：控制橙 / 设备青 / 说明紫，选中项图标与文字同色，另有半透明色块与描边 |
| 其它选中项看不见选中的字 | `WingCapsuleButtonStyle` 选中态统一「彩色渐变 + 纯白粗体字 + 内描边」，不再依赖系统 `accentColor`；`WingAppearance.configure()` 把分段控件选中段设为橙底白字、未选中浅灰字，`UISwitch` 开启色同步；AUTO 滚轮文字固定白色 |
| 底部「尾翼控制器 / 点火升降」前的图标 | 原小程序 80×80 黑白盾形 `Logo` 换成 `WingBrandBadge()`：橙红渐变圆形 + 白色 `arrow.up.arrow.down` 升降符号（SF Symbol，不新增图片资源），HTML 预览同步为同款 CSS 徽标 |
| 赛道模式演示动画 | `TrackModeView` 整个动画卡片（`TrackAnim0..7` + `TrackStatus`）删除，只保留「刹车幅度设定 / a 值 / 强中弱」；`Preview/index.html` 同步删除；点火成功弹层的 `FireAnim` 动画保留 |

`Assets.xcassets` 里 `TrackAnim*` / `TrackStatus` 素材仍在（未删资源，便于以后恢复），只是不再被引用。静态预检新增 `check_ui_wiring()`，会拦截「改回浅色 / 改回系统 TabView / 恢复赛道动画 / 换回旧 Logo」。

---

## 3. 目录结构

```
WingControl-iOS/                              # ← 作为 GitHub 仓库根目录
├── .github/workflows/build-ipa.yml           # GitHub Actions 自动归档并导出 IPA
├── .gitignore                                # 忽略 build/ 与签名材料
├── .gitattributes                            # 强制 LF 换行（CI bash 脚本必需）
├── WingControl.xcodeproj/
│   ├── project.pbxproj                       # 手工生成的完整 Xcode 工程
│   ├── project.xcworkspace/
│   └── xcshareddata/xcschemes/WingControl.xcscheme   # 共享 Scheme，CI 必需
├── WingControl/
│   ├── Info.plist                            # 应用名称、图标名、场景代理、蓝牙权限、启动屏、方向
│   ├── Assets.xcassets/                      # 25 个 imageset + AppIcon + 2 个 colorset
│   ├── App/WingControlApp.swift              # 应用入口 + SceneDelegate + 全局外观 + SwiftUI 根视图
│   ├── Model/
│   │   ├── WingProtocol.swift                # 指令帧编解码、速度校验、档位映射
│   │   └── WingUIState.swift                 # 页面状态、弹窗、日志模型
│   ├── Services/
│   │   ├── BLEManager.swift                  # CBCentralManager / CBPeripheral 封装
│   │   ├── WingController.swift              # 状态机、动作分发、回复解析、演示模式
│   │   └── Haptics.swift                     # 触觉反馈
│   ├── Theme/Theme.swift                     # 深色配色、彩色选中渐变、8pt 间距
│   └── Views/
│       ├── RootTabView.swift                 # 自定义彩色底部标签栏 + 弹层 + 全局提示
│       ├── ControlView.swift                 # 主控制页 + 彩色品牌徽标 + 底部点火按钮
│       ├── DailyModeView.swift               # 日常模式：档位 / 一键 / AUTO
│       ├── TrackModeView.swift               # 赛道模式：刹车灵敏度（演示动画已移除）
│       ├── DeviceView.swift                  # 扫描、连接、协议诊断、命令日志
│       ├── InfoView.swift                    # 说明、协议、启动日志
│       └── Components.swift                  # 通用组件 + 双列滚轮 + 逐帧动画
├── Preview/index.html                        # 单文件交互原型（图片已内嵌 base64）
└── tools/
    ├── build-ipa.sh                          # archive + 导出 IPA（CI 与本地共用）
    ├── verify_swift_sources.py               # Swift 源码静态预检（无需 Xcode）
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

- `did`：**设备认可的主机 ID**。原小程序首次启动随机生成 0~255 并持久化（`wx.setStorage({key:"did"})`），设备会把已配对的 did 记下来；App 首次启动随机生成的值往往不同，必须按状态帧回传值同步，否则命令会被静默忽略（见第 2 节「指令发送后设备毫无反应的修复」）。
- 所有速度值以十六进制单字节发送，例如 80 km/h → `0x50`。

| 功能 | 帧 |
| --- | --- |
| 设置档位 | `BB did 80 01 step 00` |
| 自动升降 | `BB did 80 02 down up` |
| 关闭自动 | `BB did 80 03 00 00` |
| 赛道灵敏度（强/中/弱 = 1/2/3） | `BB did 80 04 type 00` |
| 点火升降（关/开 = 0/1） | `BB did 80 05 on 00` |
| 一键上升 / 下降 | `BB did 80 06 01/02 00` |

**设备 notify 上报**：至少 8 字节基础帧，以 `BB` 开头；**字节 1 是设备认可的 did**（真机日志 `BB 1C 20 01 05 00 00 A5 …` 中为 `1C`），字节 2 是帧类型 `20`，字节 3~7 依次为 `auto 标志 / 档位 / 车速 / 降速临界 / 升速临界`；12 字节扩展帧再追加 `赛道类型 / 点火开关 / 点火就绪 / 点火结果`。`auto == 2` 表示自动模式已开启。App 每次收到状态帧都会用字节 1 校正后续命令的 did。

**速度校验顺序**（左列降速 `down`、右列升速 `up`）：

1. `down == 0 && up == 0` → 弹确认框，进入校准模式；
2. `up < down + 20` → 「降速加速临界范围总大于20码」；
3. `down == 0 && up != 0` → 「下降速度必须大于零，升降都为零校准除外」；
4. `up <= down` → 「升起速度必须大于下降速度，升降都为零校准除外」。

**蓝牙设备**：扫描只接受名称以 `JDY` 开头的 BLE 模块；连接后发现主服务，优先选择同时支持 `write` 与 `notify` 的特征值（JDY 常见 `FFE0/FFE1`），否则退化为分别取可写 / 可通知特征值。写入默认用 `.withoutResponse`（与微信小程序在 iOS 上的行为一致），可在「设备 → 协议诊断」切到 `.withResponse`；若特征值只支持其中一种，代码会自动回退。无响应写不会触发 `didWriteValueFor`，日志会显式打印「命令已写入」避免误判。

运行 `python tools/verify_protocol.py` 可校验全部帧、校验规则和回复解析。

---

## 6. iOS 实现要点

- **权限时机**：`CBCentralManager` 延迟创建，只在用户点击「搜索设备 / 连接」时申请蓝牙权限；`CBCentralManager.state == .unknown` 时用 `pendingAction` 等 `.poweredOn` 后再继续，避免首次点击误报失败。
- **断线处理**：`didDisconnectPeripheral` 重置特征值并提示，可在「设备」页点「连接上次使用的设备」重连（缓存 peripheral UUID）。
- **演示模式**：无硬件 / 模拟器下模拟设备回复帧，可完整走通档位、AUTO、赛道、点火成功与失败流程；「模拟已装车内实体按键」开关用于复现点火失败分支。
- **无障碍**：所有交互元素带 `accessibilityLabel` / `accessibilityValue` / `accessibilityHint`；触控目标 ≥ 44pt；状态同时用图标 + 文字，不只用颜色。
- **外观**：固定深色主题（`UIUserInterfaceStyle=Dark` + `.preferredColorScheme(.dark)`），页面 / 卡片 / 底部栏统一用 `Theme.swift` 的黑色系，选中态一律彩色渐变 + 白字高对比；系统控件由 `WingAppearance.configure()` 显式着色，不随系统浅色模式变化；自定义字体走 `UIFont.preferredFont`，支持 Dynamic Type。
- **动效**：GIF 拆帧用 `UIImageView.animationImages` 播放，遵循「减弱动态效果」时自动静止；不使用全屏 spinner。
- **触觉**：档位、模式、校验失败、点火成功分别使用 selection / impact / notification 反馈。

---

## 7. 已知限制

1. 未做后台蓝牙与 State Restoration，App 退到后台后不保证持续连接。
2. 原小程序的商城跳转、微信登录、`navigateToMiniProgram` 在 iOS 无对应能力，已移除。
3. 原包中 `weiyistart.gif`、`logo.gif` 的长启动动画未移植，改为系统启动屏；`track_top.gif` 赛道演示动画按需求已移除（素材仍留在 Assets 中），`fire.gif` 拆帧保留在点火成功弹层。
4. 已在真机 + JDY-10M-2.3 上完成连接、服务发现与 notify 联调；早期版本因 did 与设备已配对值不一致导致命令被忽略，修复后的 **did 自动同步与写入方式切换需重新编译安装后复验**。若你的模块服务 UUID 不是 `FFE0/FFE1`，「动态发现主服务」逻辑仍可工作；特征值属性不符时可在「协议诊断」切换写入方式，必要时调整 `BLEManager.swift` 的筛选条件。
5. 工程由脚本生成并在 Windows 上完成静态校验；GitHub Actions 上已用 Xcode 16.4 / iOS 18.5 SDK 跑到 Swift 编译阶段，并按首个真实报错修复了 `.frame` 重载误用（见第 2 节）。最终 archive/导出成功仍以下一次 CI 日志为准。首次打开若 Xcode 提示升级设置，按提示确认即可。

---

## 8. 素材说明

`Assets.xcassets` 中的图片全部来自用户提供的原始小程序包（半透明 PNG 已合成到 `#0F0F0F` 深色底以适配控制画布），AppIcon 由原 `logo.png` 重新排版生成。素材版权归原小程序权利人所有，本工程仅用于功能迁移。
