import SwiftUI

/// 键盘主题 token，近似 iOS 26 简体拼音键盘视觉。键帽纯色无任何效果，面板透明
/// 由系统容器绘制；浅色不透明，深色为半透明叠加（经 ≈#2B2B2B 系统背板混合），
/// 深浅色由 `@Environment(\.colorScheme)` 自动跟随。
public struct Theme {
    public let keyBackground: Color
    public let specialKeyBackground: Color
    /// 按键按压时的填充色（浅色变暗 / 深色变亮，原生同款；所有键型共用）。
    public let pressedKeyBackground: Color
    public let keyForeground: Color
    public let specialKeyForeground: Color
    /// 预览气泡背景：必须不透明，否则深色下透出键缝显得「透明」。
    public let previewBubbleBackground: Color
    public let keyCornerRadius: CGFloat
    public let keyHeight: CGFloat
    public let keySpacing: CGFloat
    public let rowSpacing: CGFloat
    public let keyboardPadding: EdgeInsets
    public let candidateBarHeight: CGFloat
    public let candidateSelectionFill: Color
    /// 候选栏右侧展开/收起箭头宽度（候选网格首行避让宽度）。
    public let chevronWidth: CGFloat
    /// 候选单元格高度（折叠态选中背景与展开网格单元格一致）。
    public let candidateCellHeight: CGFloat
    /// 选中候选 pill 高度（略高于普通候选，上下留白更大）。
    public let candidateSelectionHeight: CGFloat
    /// 选中候选文字与背景的左右边距（普通候选用 10，选中收紧到该值）。
    public let candidateSelectionHPadding: CGFloat
    /// 选中候选 pill 圆角。
    public let candidateSelectionCornerRadius: CGFloat
    /// 候选文字字号（与 `candidateFont` 一致，供文本宽度测量）。
    public let candidateCellFontSize: CGFloat
    /// 特殊键（123 / ABC / 中英切换 / 回车等）的文字字号。
    public let specialKeyFontSize: CGFloat
    /// 同步 toast 文字字号与内边距。
    public let toastFontSize: CGFloat
    public let toastHPadding: CGFloat
    public let toastVPadding: CGFloat
    /// 字符键按压气泡：边长 / 圆角 / 上移偏移 / 字号。
    public let previewBubbleSide: CGFloat
    public let previewBubbleCornerRadius: CGFloat
    public let previewBubbleOffsetY: CGFloat
    public let previewFontSize: CGFloat
    /// 功能键图标（退格 / shift）字号。
    public let iconFontSize: CGFloat
    /// 候选展开箭头字号。
    public let chevronIconFontSize: CGFloat
    public let font: Font
    public let candidateFont: Font

    /// 键盘内容总高度：候选栏 + 键区 + 内边距。
    public var totalHeight: CGFloat {
        candidateBarHeight
            + keyboardPadding.top
            + 4 * keyHeight
            + 3 * rowSpacing
            + keyboardPadding.bottom
    }

    public nonisolated(unsafe) static let light = Theme(
        keyBackground: Color(hex: 0xFFFFFF),
        specialKeyBackground: Color(hex: 0xFFFFFF),
        pressedKeyBackground: Color(hex: 0xF0F1F3),
        keyForeground: Color(hex: 0x171717),
        specialKeyForeground: Color(hex: 0x171717),
        previewBubbleBackground: Color(hex: 0xFFFFFF),
        candidateSelectionFill: Color(hex: 0xF6F8F9),
        geometry: base
    )

    public nonisolated(unsafe) static let dark = Theme(
        // 半透明叠加：由 `overlay(base:target:)` 反解 alpha，经系统深色背板
        // （`darkBackdrop` ≈ #2B2B2B）混合后精确命中目标观感色。
        keyBackground: Theme.overlay(target: 0x585858),
        specialKeyBackground: Theme.overlay(base: 0x858585, target: 0x3A3A3A),
        pressedKeyBackground: Theme.overlay(target: 0x6B6B6B),
        keyForeground: Color(hex: 0xFFFFFF),
        specialKeyForeground: Color(hex: 0xFFFFFF),
        previewBubbleBackground: Color(hex: 0x585858),
        candidateSelectionFill: Theme.overlay(target: 0x5A5A5A),
        geometry: base
    )

    // 深浅色共享的几何/字体 token，单一来源。
    private static let base = ThemeGeometry(
        keyCornerRadius: 8,
        keyHeight: 45,
        keySpacing: 6,
        rowSpacing: 11,
        keyboardPadding: EdgeInsets(top: 8, leading: 7, bottom: 5, trailing: 7),
        candidateBarHeight: 40,
        chevronWidth: 34,
        candidateCellHeight: 32,
        candidateSelectionHeight: 34,
        candidateSelectionHPadding: 6,
        candidateSelectionCornerRadius: 9,
        candidateCellFontSize: 19,
        specialKeyFontSize: 17,
        toastFontSize: 15,
        toastHPadding: 16,
        toastVPadding: 9,
        previewBubbleSide: 48,
        previewBubbleCornerRadius: 10,
        previewBubbleOffsetY: -47,
        previewFontSize: 30,
        iconFontSize: 21,
        chevronIconFontSize: 13,
        font: .system(size: 24, weight: .regular),
        candidateFont: .system(size: 19, weight: .regular)
    )

    private init(
        keyBackground: Color,
        specialKeyBackground: Color,
        pressedKeyBackground: Color,
        keyForeground: Color,
        specialKeyForeground: Color,
        previewBubbleBackground: Color,
        candidateSelectionFill: Color,
        geometry: ThemeGeometry
    ) {
        self.keyBackground = keyBackground
        self.specialKeyBackground = specialKeyBackground
        self.pressedKeyBackground = pressedKeyBackground
        self.keyForeground = keyForeground
        self.specialKeyForeground = specialKeyForeground
        self.previewBubbleBackground = previewBubbleBackground
        self.candidateSelectionFill = candidateSelectionFill
        self.keyCornerRadius = geometry.keyCornerRadius
        self.keyHeight = geometry.keyHeight
        self.keySpacing = geometry.keySpacing
        self.rowSpacing = geometry.rowSpacing
        self.keyboardPadding = geometry.keyboardPadding
        self.candidateBarHeight = geometry.candidateBarHeight
        self.chevronWidth = geometry.chevronWidth
        self.candidateCellHeight = geometry.candidateCellHeight
        self.candidateSelectionHeight = geometry.candidateSelectionHeight
        self.candidateSelectionHPadding = geometry.candidateSelectionHPadding
        self.candidateSelectionCornerRadius = geometry.candidateSelectionCornerRadius
        self.candidateCellFontSize = geometry.candidateCellFontSize
        self.specialKeyFontSize = geometry.specialKeyFontSize
        self.toastFontSize = geometry.toastFontSize
        self.toastHPadding = geometry.toastHPadding
        self.toastVPadding = geometry.toastVPadding
        self.previewBubbleSide = geometry.previewBubbleSide
        self.previewBubbleCornerRadius = geometry.previewBubbleCornerRadius
        self.previewBubbleOffsetY = geometry.previewBubbleOffsetY
        self.previewFontSize = geometry.previewFontSize
        self.iconFontSize = geometry.iconFontSize
        self.chevronIconFontSize = geometry.chevronIconFontSize
        self.font = geometry.font
        self.candidateFont = geometry.candidateFont
    }
}

/// 深浅色主题共享的几何/字体 token。
private struct ThemeGeometry {
    let keyCornerRadius: CGFloat
    let keyHeight: CGFloat
    let keySpacing: CGFloat
    let rowSpacing: CGFloat
    let keyboardPadding: EdgeInsets
    let candidateBarHeight: CGFloat
    let chevronWidth: CGFloat
    let candidateCellHeight: CGFloat
    let candidateSelectionHeight: CGFloat
    let candidateSelectionHPadding: CGFloat
    let candidateSelectionCornerRadius: CGFloat
    let candidateCellFontSize: CGFloat
    let specialKeyFontSize: CGFloat
    let toastFontSize: CGFloat
    let toastHPadding: CGFloat
    let toastVPadding: CGFloat
    let previewBubbleSide: CGFloat
    let previewBubbleCornerRadius: CGFloat
    let previewBubbleOffsetY: CGFloat
    let previewFontSize: CGFloat
    let iconFontSize: CGFloat
    let chevronIconFontSize: CGFloat
    let font: Font
    let candidateFont: Font
}

public extension View {
    /// 键帽背景：纯色圆角填充，按压切换到统一按压底色。
    @ViewBuilder
    func keyBackground(
        isPressed: Bool,
        style: KeyStyle,
        theme: Theme
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: theme.keyCornerRadius, style: .continuous)
                .fill(theme.fillColor(style: style, isPressed: isPressed))
        )
    }

    /// 悬浮元素（字符键按压气泡 / 同步 toast）共用阴影规格。
    func floatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
    }
}

public extension Theme {
    /// 确认（回车）键底色：单一常量，与 fcitx5-ios `highlightBackground` 一致。
    static let confirmKeyColor = Color(hex: 0x007AFF)

    /// 键帽填充色（含按压态）：按压统一 pressedKeyBackground。纯函数供测试共用。
    func fillColor(style: KeyStyle, isPressed: Bool) -> Color {
        switch style {
        case .confirm:
            return isPressed ? pressedKeyBackground : Theme.confirmKeyColor
        case .special:
            return isPressed ? pressedKeyBackground : specialKeyBackground
        case .normal:
            return isPressed ? pressedKeyBackground : keyBackground
        }
    }
}

extension Color {
    /// 0xRRGGBB 十六进制颜色。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
