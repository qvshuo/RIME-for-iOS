import SwiftUI
import UIKit

public struct Theme {
    public var panelBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    public let keyBackground: Color
    public let specialKeyBackground: Color
    public let pressedKeyBackground: Color
    public let keyForeground: Color
    public let specialKeyForeground: Color
    /// 气泡必须不透明，避免键缝透出。
    public let previewBubbleBackground: Color
    public let keyCornerRadius: CGFloat
    public let keyHeight: CGFloat
    public let keySpacing: CGFloat
    public let rowSpacing: CGFloat
    public let keyboardPadding: EdgeInsets
    public let candidateBarHeight: CGFloat
    public let candidateSelectionFill: Color
    public let chevronWidth: CGFloat
    public let candidateCellHeight: CGFloat
    public let candidateSelectionHeight: CGFloat
    public let candidateSelectionHPadding: CGFloat
    public let candidateSelectionCornerRadius: CGFloat
    /// 字号须与 candidateFont 一致，否则测量和实际排版不符。
    public let candidateCellFontSize: CGFloat
    public let specialKeyFontSize: CGFloat
    public let toastFontSize: CGFloat
    public let toastHPadding: CGFloat
    public let toastVPadding: CGFloat
    public let previewBubbleSide: CGFloat
    public let previewBubbleCornerRadius: CGFloat
    public let previewBubbleOffsetY: CGFloat
    public let previewFontSize: CGFloat
    public let iconFontSize: CGFloat
    public let chevronIconFontSize: CGFloat
    public let font: Font
    public let candidateFont: Font

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

    func floatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
    }
}

public extension Theme {
    static let confirmKeyColor = Color(hex: 0x007AFF)

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
