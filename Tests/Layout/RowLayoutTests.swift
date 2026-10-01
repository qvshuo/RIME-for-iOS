import Testing
import UIKit
import KeyboardModels
@testable import KeyboardUI

struct RowLayoutTests {
    private func key(
        _ label: String,
        _ action: KeyAction,
        width: CGFloat = 1.0,
        fixed: CGFloat? = nil
    ) -> KeyDescriptor {
        KeyDescriptor(label: label, action: action, style: .normal, width: width, fixedWidth: fixed)
    }

    private func layout(
        _ keys: [KeyDescriptor],
        totalWidth: CGFloat,
        sideInset: CGFloat = 0,
        minSpaceWidth: CGFloat = 90,
        returnLabelWidth: CGFloat = 0
    ) -> RowLayout {
        RowLayoutMath.layout(RowLayoutParameters(
            keys: keys,
            totalWidth: totalWidth,
            sideInset: sideInset,
            keyboardLeading: 7,
            keyboardTrailing: 7,
            keySpacing: 6,
            keyHeight: 45,
            minSpaceWidth: minSpaceWidth,
            returnLabelWidth: returnLabelWidth
        ))
    }

    private func fills(_ result: RowLayout, gridWidth: CGFloat) -> Bool {
        let total = result.widths.reduce(0, +) + result.gaps.reduce(0, +) + result.sideInset * 2
        return abs(total - gridWidth) < 0.01
    }

    @Test("底行：固定宽键 + 空格吸余量 + 回车 1.5×方形")
    func bottomRowFixedAndFlexSpace() {
        let keys = [
            key("123", .numbers, fixed: 67.5),
            key("", .space, width: 5),
            key("中", .toggleLanguage, fixed: 45),
            key("⏎", .return, width: 1.5),
        ]
        let result = layout(keys, totalWidth: 393, returnLabelWidth: 40)
        // gridWidth = 379；空格 = 379 − 3×6 − 67.5 − 45 − 67.5 = 181
        #expect(result.widths == [67.5, 181, 45, 67.5])
        #expect(result.gaps == [6, 6, 6])
        #expect(result.sideInset == 0)
        #expect(fills(result, gridWidth: 379))
    }

    @Test("底行：长回车文案从空格借宽，空格保底")
    func bottomRowLongReturnLabel() {
        let keys = [
            key("123", .numbers, fixed: 67.5),
            key("", .space, width: 5),
            key("中", .toggleLanguage, fixed: 45),
            key("⏎", .return, width: 1.5),
        ]
        let result = layout(keys, totalWidth: 393, returnLabelWidth: 200)
        // maxReturn = 379 − 18 − 112.5 − 90 = 158.5
        #expect(abs(result.widths[1] - 90) < 0.01)
        #expect(abs(result.widths[3] - 158.5) < 0.01)
        #expect(result.widths[0] == 67.5)
        #expect(result.widths[2] == 45)
        #expect(fills(result, gridWidth: 379))
    }

    @Test("字母页第三行：z 对齐 s、m 对齐 k，⇧/⌫ 贴边")
    func shiftRowAlignsZM() {
        let letters = ["z", "x", "c", "v", "b", "n", "m"].map { key($0, .character($0)) }
        let keys = [key("⇧", .shift, fixed: 45)] + letters + [key("⌫", .backspace, fixed: 45)]
        let result = layout(keys, totalWidth: 393)

        let gridWidth: CGFloat = 379
        let letter: CGFloat = (gridWidth - 9 * 6) / 10 // 32.5
        // g = (gridWidth − 2×45 − 7L − 6×6)/2 = 1.5L − 36
        let gap = (gridWidth - 2 * 45 - 7 * letter - 6 * 6) / 2

        #expect(result.widths[0] == 45)
        #expect(result.widths[8] == 45)
        for i in 1...7 {
            #expect(result.widths[i] == letter)
        }
        #expect(result.gaps[0] == gap)
        #expect(result.gaps[7] == gap)
        for i in 1...6 {
            #expect(result.gaps[i] == 6)
        }
        #expect(result.sideInset == 0)
        #expect(fills(result, gridWidth: gridWidth))

        // 对齐：z.x == s.x、m.x == k.x（第一行 9 字母居中，行首留白 (L+6)/2）
        let row1Padding = (letter + 6) / 2
        let sX = row1Padding + letter + 6
        let zX = result.widths[0] + result.gaps[0]
        #expect(abs(zX - sX) < 0.01)

        let kX = row1Padding + 7 * letter + 7 * 6
        let mX = result.widths[0] + result.gaps[0] + 6 * letter + 6 * 6
        #expect(abs(mX - kX) < 0.01)
    }

    @Test("数字/符号页第三行：切换/退格方形，中间键弹性分摊")
    func toggleRowSpecialsSquareMiddleFlex() {
        let keys = [
            key("#+=", .symbols, fixed: 45),
            key("。", .character("。")),
            key("，", .character("，")),
            key("、", .character("、")),
            key("？", .character("？")),
            key("！", .character("！")),
            key(".", .character(".")),
            key("⌫", .backspace, fixed: 45),
        ]
        let result = layout(keys, totalWidth: 393)
        // 中间键 = (379 − 90 − 7×6)/6 = 247/6
        #expect(result.widths[0] == 45)
        #expect(result.widths[7] == 45)
        #expect(abs(result.widths[1] - 247.0 / 6) < 0.01)
        for i in 1...6 {
            #expect(abs(result.widths[i] - result.widths[1]) < 0.01)
        }
        #expect(result.sideInset == 0)
        #expect(fills(result, gridWidth: 379))
    }

    @Test("纯字符行：10 键满宽、9 键居中")
    func letterRows() {
        let letter: CGFloat = (379 - 9 * 6) / 10

        let ten = (0..<10).map { key(String($0), .character(String($0))) }
        let r10 = layout(ten, totalWidth: 393)
        #expect(r10.widths.allSatisfy { abs($0 - letter) < 0.01 })
        #expect(r10.sideInset == 0)
        #expect(fills(r10, gridWidth: 379))

        let nine = (0..<9).map { key(String($0), .character(String($0))) }
        let r9 = layout(nine, totalWidth: 393)
        #expect(r9.widths.allSatisfy { abs($0 - letter) < 0.01 })
        #expect(abs(r9.sideInset - (letter + 6) / 2) < 0.01)
        #expect(fills(r9, gridWidth: 379))
    }

    @Test("兜底：非上述结构行按权重分摊并保留 leadingPadding")
    func weightedFallback() {
        let keys = [
            key("a", .symbols, width: 1),
            key("b", .numbers, width: 3),
        ]
        let result = layout(keys, totalWidth: 393, sideInset: 10)
        let keyUnit: CGFloat = 379 - 20 - 6
        #expect(abs(result.widths[0] - keyUnit / 4) < 0.01)
        #expect(abs(result.widths[1] - keyUnit * 3 / 4) < 0.01)
        #expect(result.sideInset == 10)
        #expect(fills(result, gridWidth: 379))
    }

    @Test("兜底：权重全 0 时等宽分摊，不除零不出 NaN")
    func weightedFallbackZeroWeight() {
        let keys = [
            key("a", .symbols, width: 0),
            key("b", .numbers, width: 0),
        ]
        let result = layout(keys, totalWidth: 393, sideInset: 10)
        let keyUnit: CGFloat = 379 - 20 - 6
        #expect(result.widths.allSatisfy { $0.isFinite })
        #expect(abs(result.widths[0] - keyUnit / 2) < 0.01)
        #expect(abs(result.widths[1] - keyUnit / 2) < 0.01)
        #expect(fills(result, gridWidth: 379))
    }

}
