import SwiftUI
import UIKit

// MARK: - 全局控件外观（深色主题 + 彩色选中态）

/// 手写 Info.plist + 手写工程不会自动带 Xcode 模板的外观设置，
/// 这里显式配置系统控件，避免「选中后文字和背景同色看不见」。
enum WingAppearance {
    static func configure() {
        let accent = UIColor(Color.wingAccent)

        // 全局兜底：任何仍由 UIKit 决定文字 / tint 的系统控件
        // 统一使用高饱和橙色，避免在深色底上被判成深色文字而「字不见了」。
        UIView.appearance().tintColor = accent

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = accent
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)],
            for: .selected
        )
        segmented.setTitleTextAttributes(
            [.foregroundColor: UIColor(white: 0.78, alpha: 1), .font: UIFont.systemFont(ofSize: 13, weight: .medium)],
            for: .normal
        )

        UISwitch.appearance().onTintColor = accent

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(Color.wingBackground)
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(Color.wingAccent)
    }
}

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
        WingAppearance.configure()
        NSLog("[WingControl] 1/4 application didFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
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
        // 占位界面是「深灰底 + 浅色文字」，与全黑主题协调；真正的黑屏是纯黑且没有字，
        // 两者仍能一眼区分，Console 也能据日志定位。
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = UIColor(Color.wingBackground)
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

/// 纯 UIKit 占位：深灰底 + 一行浅色 Dynamic Type 文字，无交互、无全屏 spinner。
/// 只用于区分「窗口已创建」与「SwiftUI 界面加载失败」，正常启动下一闪而过。
/// 工程保持零第三方依赖，这里用原生 NSLayoutConstraint 而不是引入 SnapKit。
private final class LaunchPlaceholderController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Color.wingSurface)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let label = UILabel()
        label.text = "尾翼控制器"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.accessibilityLabel = "尾翼控制器"
        stack.addArrangedSubview(label)

        let detail = UILabel()
        detail.text = "正在启动…"
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = UIColor(white: 0.72, alpha: 1)
        detail.textAlignment = .center
        stack.addArrangedSubview(detail)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -16)
        ])
    }
}

// MARK: - SwiftUI 界面根

struct WingRootView: View {
    var body: some View {
        RootTabView()
            .background(Color.wingBackground.ignoresSafeArea())
            // 强制深色：让 List / NavigationStack / 语义色与全黑主题一致
            .preferredColorScheme(.dark)
    }
}
