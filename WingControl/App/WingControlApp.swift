import SwiftUI
import UIKit

// MARK: - 应用入口（UIKit 生命周期 + SwiftUI 界面）

/// 本工程的 Info.plist 与 pbxproj 均为手工生成，不走 Xcode 的
/// 「Generate Info.plist File」，因此不能使用 SwiftUI 隐式场景生命周期：
/// 系统在 Info.plist 里看到 UIApplicationSceneManifest 却没有可用的
/// UISceneConfigurations / scene delegate 时，会创建场景但不创建窗口，
/// 界面就一直停在启动屏（表现为黑屏）。
///
/// 这里改为显式入口：AppDelegate 提供场景配置，SceneDelegate 亲自创建
/// UIWindow 并装载 SwiftUI 根视图，从根上保证一定有一个可见窗口。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        NSLog("[WingControl] application didFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
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
        guard let windowScene = scene as? UIWindowScene else { return }

        let model = WingController()
        controller = model

        let window = UIWindow(windowScene: windowScene)
        // 明确的浅色底：即便 SwiftUI 根视图加载失败，也不会是一整块黑屏
        window.backgroundColor = .systemBackground
        window.rootViewController = UIHostingController(
            rootView: WingRootView().environmentObject(model)
        )
        window.makeKeyAndVisible()
        self.window = window
        NSLog("[WingControl] window installed, root view attached")
    }
}

// MARK: - SwiftUI 界面根

struct WingRootView: View {
    var body: some View {
        RootTabView()
            .background(Color(uiColor: .systemBackground))
    }
}
