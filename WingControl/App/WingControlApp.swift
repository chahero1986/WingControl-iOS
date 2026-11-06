import SwiftUI

@main
struct WingControlApp: App {
    // 蓝牙权限不在启动时申请：CBCentralManager 只在用户点击「搜索设备」时才创建
    @StateObject private var controller = WingController()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(controller)
        }
    }
}
