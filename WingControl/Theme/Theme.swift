import SwiftUI

extension Color {
    /// 与原小程序 #0f0f0f 一致的深色控制画布；半透明素材已预先合成到该底色
    static let wingCanvas = Color(red: 0.059, green: 0.059, blue: 0.059)
    static let wingBorder = Color(red: 0.27, green: 0.27, blue: 0.27)

    // MARK: 深色主题：页面纯黑系，卡片略亮，靠边框分层
    static let wingBackground = Color(red: 0.059, green: 0.059, blue: 0.059)   // #0F0F0F 页面底
    static let wingSurface = Color(red: 0.110, green: 0.110, blue: 0.118)       // #1C1C1E 卡片
    static let wingSurfaceAlt = Color(red: 0.165, green: 0.165, blue: 0.176)    // #2A2A2D 次级控件
    static let wingTabBar = Color(red: 0.078, green: 0.078, blue: 0.086)        // #141416 底部栏
    static let wingTextSecondary = Color(red: 0.66, green: 0.66, blue: 0.70)
    static let wingTabInactive = Color(red: 0.56, green: 0.56, blue: 0.60)

    // MARK: 彩色强调色：选中态必须一眼看得见，绝不能用「和背景同色」的语义色
    static let wingAccent = Color(red: 1.000, green: 0.420, blue: 0.180)        // 橙 #FF6B2E
    static let wingAccentWarm = Color(red: 1.000, green: 0.255, blue: 0.420)    // 粉红 #FF416B
    static let wingControlTint = Color(red: 1.000, green: 0.500, blue: 0.220)   // 控制 Tab 橙
    static let wingDeviceTint = Color(red: 0.200, green: 0.840, blue: 0.760)    // 设备 Tab 青
    static let wingInfoTint = Color(red: 0.680, green: 0.560, blue: 0.980)      // 说明 Tab 紫

    /// 选中态统一使用的彩色渐变，保证白字在上面有足够对比度
    static var wingAccentGradient: LinearGradient {
        LinearGradient(
            colors: [.wingAccent, .wingAccentWarm],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// 8pt 网格：所有间距使用 8 的倍数
enum Spacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 16
    static let md: CGFloat = 24
    static let lg: CGFloat = 32
}
