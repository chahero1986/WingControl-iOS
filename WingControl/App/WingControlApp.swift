import SwiftUI
import UIKit

// MARK: - 应用入口（UIKit 生命周期 + SwiftUI 界面）

/// 本工程的 Info.plist 与 pbxproj 均为手工生成，不走 Xcode 的
/// 「Generate Info.plist File」，因此不能使用 SwiftUI 隐式场景生命周期：
/// 系统在 Info.plist 里看到 UIApplicationSceneManifest 却没有可用的
/// UISceneConfigurations / scene delegate 时，会创建场景但不创建窗口，
/// 界面就一直停在启动屏（表现为黑屏）。
///
/// 这里用显式入口：AppDelegate 提供场景配置，SceneDelegate 先创建并显示
/// UIWindow，再装载 SwiftUI 根视图，从根上保证一定有一个可见窗口。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        NSLog("[WingControl] 1/4 application didFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 名称与 Info.plist 的 UISceneConfigurations 保持一致；
        // delegateClass 用类型而非字符串，不受 Product Module Name 影响。
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        NSLog("[WingControl] 2/4 configurationForConnecting, role=\(connectingSceneSession.role.rawValue)")
        return configuration
    }
}

// MARK: - 窗口创建

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    /// 强持有状态机，避免仅靠 environment 传递时被提前释放
    private var controller: WingController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            NSLog("[WingControl] willConnectTo 失败：scene 不是 UIWindowScene（\(type(of: scene))）")
            return
        }

        // 关键顺序：先建立一个必定可见的窗口并上屏，再加载状态机与 SwiftUI 根视图。
        // 若后续环节异常，用户看到的是浅色占位界面而不是整屏黑，Console 也能据日志定位。
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .systemBackground
        window.rootViewController = LaunchPlaceholderController()
        window.makeKeyAndVisible()
        self.window = window
        NSLog("[WingControl] 3/4 window installed with placeholder")

        let model = WingController()
        controller = model
        window.rootViewController = UIHostingController(
            rootView: WingRootView().environmentObject(model)
        )
        NSLog("[WingControl] 4/4 SwiftUI root view attached")
    }
}

// MARK: - 启动占位界面

/// 纯 UIKit 占位：浅色语义色背景 + 一行 Dynamic Type 文字，无交互、无全屏 spinner。
/// 只用于区分「窗口已创建」与「SwiftUI 界面加载失败」，正常启动下一闪而过。
/// 工程保持零第三方依赖，这里用原生 NSLayoutConstraint 而不是引入 SnapKit。
private final class LaunchPlaceholderController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "尾翼控制器"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.accessibilityLabel = "尾翼控制器"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16)
        ])
    }
}

// MARK: - SwiftUI 界面根

struct WingRootView: View {
    var body: some View {
        RootTabView()
            .background(Color(uiColor: .systemBackground))
    }
}
