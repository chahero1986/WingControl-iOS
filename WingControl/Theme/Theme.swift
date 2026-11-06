import SwiftUI

extension Color {
    /// 与原小程序 #0f0f0f 一致的深色控制画布；半透明素材已预先合成到该底色
    static let wingCanvas = Color(red: 0.059, green: 0.059, blue: 0.059)
    static let wingBorder = Color(red: 0.27, green: 0.27, blue: 0.27)
}

/// 8pt 网格：所有间距使用 8 的倍数
enum Spacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 16
    static let md: CGFloat = 24
    static let lg: CGFloat = 32
}
