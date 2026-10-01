import Testing
import SwiftUI
@testable import KeyboardUI

struct ThemeTests {
    @Test("键帽按压统一着色且与常态可区分，确认键保持主题蓝")
    func keyFillStates() {
        for theme in [Theme.light, .dark] {
            for (style, normal) in [(KeyStyle.normal, theme.keyBackground), (.special, theme.specialKeyBackground), (.confirm, Theme.confirmKeyColor)] {
                #expect(theme.fillColor(style: style, isPressed: false) == normal)
                #expect(theme.fillColor(style: style, isPressed: true) == theme.pressedKeyBackground)
                #expect(Theme.rgba(normal) != Theme.rgba(theme.pressedKeyBackground))
            }
        }
        #expect(Theme.confirmKeyColor == Color(hex: 0x007AFF))
    }

    @Test("浅色键帽不透明，深色叠加后达到预定对比")
    func themeContrast() {
        #expect(Theme.light.keyBackground == Color(hex: 0xFFFFFF))
        #expect(Theme.light.specialKeyBackground == Color(hex: 0xFFFFFF))
        #expect(Theme.light.pressedKeyBackground == Color(hex: 0xF0F1F3))
        for (color, targetHex) in [(Theme.dark.keyBackground, UInt32(0x575858)), (Theme.dark.specialKeyBackground, 0x3A3A3C), (Theme.dark.pressedKeyBackground, 0x6A6A6C), (Theme.dark.candidateSelectionFill, 0x595858)] {
            #expect(Theme.rgba(color).a < 1)
            let blended = Theme.blended(color)
            let target = Theme.rgba(Color(hex: targetHex))
            #expect(abs(blended.r - target.r) < 0.02)
            #expect(abs(blended.g - target.g) < 0.02)
            #expect(abs(blended.b - target.b) < 0.02)
        }
    }
}
