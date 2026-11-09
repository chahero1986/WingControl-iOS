尾翼控制器 — iOS 完整工程源码包
打包时间：2026-11-09 10:35:33
源文件目录：D:\00ios软件开发\尾翼控制\WingControl-iOS
文件总数：81（1,880,462 字节）

==============================================================
一、这个包里包含的全部已修复内容（按时间顺序）
==============================================================
1. [启动黑屏] SceneDelegate 先创建 UIWindow、装浅色占位控制器并 makeKeyAndVisible，
   再加载 SwiftUI 根视图；Info.plist 补全 UISceneConfigurations。
2. [图标空白] Info.plist 补 CFBundleIconName = AppIcon；打包脚本强制校验 Assets.car。
3. [赛道模式显示不全] AnimatedImageView 加 maxWidth 约束与内容吸附优先级。
4. [指令发出但设备无反应] 按设备状态帧第 2 字节自动同步 did 并持久化；
   默认无响应写；设备页新增「协议诊断」（手写 did / 原始帧 / 重发 / 切换写入方式）。
5. [CI] macos-15 runner、bash 3.2 兼容、Swift .frame 重载修复、LF 换行、IPA 结构校验。

==============================================================
二、版本指纹：怎么确认自己拿到的是新包
==============================================================
解压后检查以下任一文件，缺一项就是旧包，不要使用：
  · WingControl/Info.plist                      含 CFBundleIconName / AppIcon
  · WingControl/App/WingControlApp.swift        含 LaunchPlaceholderController
  · WingControl/Services/WingController.swift   含「按设备状态帧同步」与 sendRawFrame
  · WingControl/Views/DeviceView.swift          含「协议诊断」
  · WingControl/Views/TrackModeView.swift       含 maxWidth: .infinity
  · tools/build-ipa.sh                          含 CFBundleIconName 校验
安装后最直观的判断：桌面图标正常显示即新包；图标仍空白 = 装到旧 IPA。

==============================================================
三、目录与使用方式（重要：不要多套一层文件夹）
==============================================================
解压后得到 WingControl-iOS/，它本身就是「仓库根目录 / 工程根目录」：
  WingControl-iOS/
    ├── WingControl.xcodeproj/      ← Xcode 打开这个
    ├── WingControl/               ← Swift 源码、Info.plist、Assets.xcassets
    ├── .github/workflows/         ← GitHub Actions 打包工作流
    ├── tools/                     ← 打包脚本与两个自检脚本
    ├── Preview/index.html         ← 电脑上直接打开的界面预览
    ├── .gitattributes / .gitignore
    └── README.md

方式 A（Mac 本地）：解压 → 双击 WingControl.xcodeproj → 选真机 → Run。
方式 B（GitHub 打包）：把 WingControl-iOS 目录「里面」的所有文件（含隐藏的 .github、
  .gitattributes、.gitignore）推到仓库根目录，然后手动运行 Actions 的 Build IPA。
  注意 .github 必须在仓库根，放到子目录工作流不会触发。
方式 C（覆盖旧仓库）：把解压内容整体覆盖过去，务必确认 Info.plist 里已有
  CFBundleIconName，再 commit & push，最后重新跑一次 Actions 生成新 IPA。

⚠️ 旧 IPA 不会自动更新，必须重新打包并安装；安装新版前建议先卸载旧 App。

==============================================================
四、解压后自检（Windows / macOS 均可，需 Python 3）
==============================================================
  cd WingControl-iOS
  python tools/verify_swift_sources.py     # Mac 用 python3
  python tools/verify_protocol.py          # 协议 24 项
两项都应输出「通过」。FILE_CHECKSUMS.txt 是包内每个文件的 SHA256，
可用于在另一台机器上核对文件是否完整、是否被旧文件覆盖。

==============================================================
五、本次打包的逐文件指纹结果
==============================================================
  [OK] WingControl/Info.plist  含 CFBundleIconName, <string>AppIcon</string>, UISceneDelegateClassName
  [OK] WingControl/App/WingControlApp.swift  含 LaunchPlaceholderController, class SceneDelegate, makeKeyAndVisible
  [OK] WingControl/Services/WingController.swift  含 按设备状态帧同步, sendRawFrame, deviceID
  [OK] WingControl/Services/BLEManager.swift  含 withoutResponse
  [OK] WingControl/Views/DeviceView.swift  含 协议诊断
  [OK] WingControl/Views/TrackModeView.swift  含 maxWidth: .infinity
  [OK] WingControl/Views/Components.swift  含 defaultLow
  [OK] Preview/index.html  含 syncDid, 界面加载中
  [OK] tools/verify_swift_sources.py  含 CFBundleIconName, sendRawFrame
  [OK] tools/build-ipa.sh  含 Assets.car, CFBundleIconName
  [OK] tools/verify_protocol.py  含 device_id
  [OK] .github/workflows/build-ipa.yml  含 macos-15
  [OK] .gitattributes  含 eol=lf

共 81 个源文件，全部按原路径打包，未包含 .git / build / 证书 / IPA / 临时文件。
