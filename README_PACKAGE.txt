尾翼控制器 — iOS 完整工程源码包（CI 编译错误修复版）
打包时间：2026-11-09 22:03:17
源文件目录：D:\00ios软件开发\尾翼控制\WingControl-iOS
文件总数：81（1958294 字节）
※ 本包替代 10:35 / 11:11 / 11:33 / 18:59 四个旧包，那些已过时，请勿使用。

================================================================
一、这一版解决什么
================================================================
GitHub Actions（Xcode 16.4 / macOS 15）归档失败，日志：

    WingController.swift:721:19: error: cannot use optional chaining on
    non-optional value of type 'WingController'
            controller?.cancelTestWrites()
    ** ARCHIVE FAILED **  /  exit code 65

原因：WingTestRunner.start(mode:) 里先写了 `guard let controller = controller`，
局部 controller 已被解包成非可选，紧接着又对它用可选链 `controller?.`，
Swift 不允许。属性与局部绑定同名是根因。

修复：WingTestRunner 的弱引用属性由 controller 改名为 owner；
所有 `guard let controller = owner` 保持不变；对可选属性的调用统一写 owner?.，
局部非可选 controller 只用于直接调用。语义完全不变，功能与 18:59 版一致。

================================================================
二、改动文件
================================================================
· Services/WingController.swift   WingTestRunner 属性改名 owner，消除可选链编译错误
· tools/verify_swift_sources.py     新增 check_optional_chaining_shadowing()：
                                   扫描每个 guard let 所在代码块，拦截对非可选
                                   局部绑定误用 `x?.`；回归用例已验证能抓到本错误
· README.md                        静态预检说明、维护约定第 11 条、本轮修复记录
未新增 / 删除 Swift 文件，project.pbxproj 无需改动；
蓝牙协议、UI、一键协议测试矩阵全部保持 18:59 版状态。

================================================================
三、怎么编译安装（务必装这一版编译出的 IPA）
================================================================
1. 把 WingControl-iOS/ 整个目录作为仓库根目录 push 到 GitHub。
2. Actions → 构建 IPA，等构建成功，下载最新 artifact（看运行时间，别拿旧 IPA）。
3. 装好先进「设备 → 一键协议测试」，能看到面板说明装对了。
4. 若之前解压过旧 zip，别把旧目录里的工程推上去（旧目录缺一键测试与本次修复）。

一键协议测试用法（与上一版相同）：
1. 关闭「演示模式」，连上蓝牙，站在能看到尾翼的位置。
2. 点「开始标准矩阵」（约 40 项，每项约 2 秒），盯住 56pt 大号编号 #1 #2 …
3. 看到尾翼动，立刻点「★ 这个编号有效（尾翼动了）」或把编号记在纸上。
4. 跑完点「复制测试报告（发给开发者）」，粘贴到对话里发我。
5. 标准矩阵全无效时点「did 全扫描」：0x00~0xFF 共 256 项，约 3 分钟。
※ 自动判定「状态帧是否变化」只是参考，最终以亲眼看到尾翼动作的编号为准。

本机已通过：Swift 静态预检（14 文件 / 68 处 .frame，含新增可选链规则）、
协议 24 项校验、build-ipa.sh 语法、全仓 LF + UTF-8、zip CRC 与逐文件 SHA256、
解压后实跑两个自检脚本。本机是 Windows 无 Xcode / swiftc，
真机效果仍需重新 push 编译安装后验证。
