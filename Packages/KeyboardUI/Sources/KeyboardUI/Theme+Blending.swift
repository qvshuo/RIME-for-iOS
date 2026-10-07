import SwiftUI

public extension Theme {
    /// 深色叠加假定系统背板为 #2B2B2B；背板改变时须重新校准。
    nonisolated static let darkBackdrop: CGFloat = 43 / 255

    /// base 与 target 为中性灰；反解经 darkBackdrop 混合后的 alpha。
    nonisolated static func overlayAlpha(base: UInt32, target: UInt32) -> CGFloat {
        let backdrop = darkBackdrop
        let baseLevel = CGFloat((base >> 8) & 0xFF) / 255
        let targetLevel = CGFloat((target >> 8) & 0xFF) / 255
        guard baseLevel != backdrop else { return 0 }
        return max(0, min(1, (targetLevel - backdrop) / (baseLevel - backdrop)))
    }

    nonisolated static func overlay(
        base: UInt32 = 0xFFFFFF,
        target: UInt32
    ) -> Color {
        Color(hex: base).opacity(overlayAlpha(base: base, target: target))
    }
}
