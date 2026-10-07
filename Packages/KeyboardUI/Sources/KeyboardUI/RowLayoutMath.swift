import Foundation
import KeyboardModels
import Synchronization
import UIKit

enum ReturnLabelWidth {
    private static let cache = Mutex<[String: CGFloat]>([:])

    static func measure(_ label: String, fontSize: CGFloat) -> CGFloat {
        let key = "\(fontSize)|\(label)"
        if let width = cache.withLock({ $0[key] }) {
            return width
        }
        let width = (label as NSString)
            .size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width + 12
        cache.withLock { $0[key] = width }
        return width
    }
}

/// widths 对应键位，gaps 对应相邻键间距；sideInset 为两侧留白。
struct RowLayout {
    let keys: [KeyDescriptor]
    let widths: [CGFloat]
    let gaps: [CGFloat]
    let sideInset: CGFloat

    init(keys: [KeyDescriptor], widths: [CGFloat], gaps: [CGFloat], sideInset: CGFloat) {
        self.keys = keys
        self.widths = widths
        self.gaps = gaps
        self.sideInset = sideInset
    }
}

struct RowLayoutParameters {
    let keys: [KeyDescriptor]
    let totalWidth: CGFloat
    let sideInset: CGFloat
    let keyboardLeading: CGFloat
    let keyboardTrailing: CGFloat
    let keySpacing: CGFloat
    let keyHeight: CGFloat
    let minSpaceWidth: CGFloat
    let returnLabelWidth: CGFloat
}

enum RowLayoutMath {
    static func layout(_ parameters: RowLayoutParameters) -> RowLayout {
        let keys = parameters.keys
        let totalWidth = parameters.totalWidth
        let sideInset = parameters.sideInset
        let keyboardLeading = parameters.keyboardLeading
        let keyboardTrailing = parameters.keyboardTrailing
        let keySpacing = parameters.keySpacing
        let keyHeight = parameters.keyHeight
        let minSpaceWidth = parameters.minSpaceWidth
        let returnLabelWidth = parameters.returnLabelWidth
        let gridWidth = totalWidth - keyboardLeading - keyboardTrailing
        // 字母格宽：以 10 键行推导，全键盘共用（对齐计算的基础单位）。
        // 窄屏下计算结果可能为负，限制为零以避免无效帧宽。
        let letter = max(0, (gridWidth - 9 * keySpacing) / 10)

        if keys.contains(where: { $0.action.isSpace }) {
            return bottomRow(
                keys: keys,
                gridWidth: gridWidth,
                sideInset: sideInset,
                keySpacing: keySpacing,
                keyHeight: keyHeight,
                minSpaceWidth: minSpaceWidth,
                returnLabelWidth: returnLabelWidth
            )
        }
        if keys.contains(where: { $0.action.isShift }) {
            return shiftRow(
                keys: keys,
                gridWidth: gridWidth,
                letter: letter,
                square: keyHeight,
                keySpacing: keySpacing
            )
        }
        if keys.contains(where: { $0.action.isToggle }),
           keys.contains(where: { $0.action.isBackspace }) {
            return toggleRow(keys: keys, gridWidth: gridWidth, square: keyHeight, keySpacing: keySpacing)
        }
        if keys.allSatisfy({ $0.action.isCharacter }) {
            return letterRow(keys: keys, letter: letter, keySpacing: keySpacing, sideInset: sideInset)
        }
        return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing)
    }

    private static func bottomRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        sideInset: CGFloat,
        keySpacing: CGFloat,
        keyHeight: CGFloat,
        minSpaceWidth: CGFloat,
        returnLabelWidth: CGFloat
    ) -> RowLayout {
        guard let spaceIndex = keys.firstIndex(where: { $0.action.isSpace }),
              let returnIndex = keys.firstIndex(where: { $0.action.isReturn }),
              spaceIndex != returnIndex else { return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing) }

        var otherFixed: CGFloat = 0
        for i in keys.indices where i != spaceIndex && i != returnIndex {
            guard let fixed = keys[i].fixedWidth else {
                return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing)
            }
            otherFixed += fixed
        }

        let returnMin = keys[returnIndex].fixedWidth ?? keyHeight * 1.5
        var returnWidth = max(returnMin, returnLabelWidth)
        // 文案过长时以「空格保底」为上限让出，总量守恒。
        let maxReturn = max(0, gridWidth - CGFloat(keys.count - 1) * keySpacing - otherFixed - minSpaceWidth)
        returnWidth = min(returnWidth, maxReturn)
        let spaceWidth = max(0, gridWidth - CGFloat(keys.count - 1) * keySpacing - otherFixed - returnWidth)

        var widths = [CGFloat](repeating: 0, count: keys.count)
        for i in keys.indices {
            if i == spaceIndex {
                widths[i] = spaceWidth
            } else if i == returnIndex {
                widths[i] = returnWidth
            } else if let fixed = keys[i].fixedWidth {
                widths[i] = fixed
            }
        }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: sideInset
        )
    }

    /// 对称间隙由行宽守恒推导，使 z/s 与 m/k 左边缘对齐。
    private static func shiftRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        letter: CGFloat,
        square: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        guard let shiftIndex = keys.firstIndex(where: { $0.action.isShift }),
              let backspaceIndex = keys.firstIndex(where: { $0.action.isBackspace }),
              shiftIndex != backspaceIndex,
              // 对齐空隙的计算假定 ⇧ 在行首、⌫ 在行尾；布局异常时退回权重分摊，
              // 避免 gaps[backspaceIndex - 1] 静默改错键位间隙。
              shiftIndex == 0,
              backspaceIndex == keys.count - 1 else {
            return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: 0, keySpacing: keySpacing)
        }
        let middleCount = keys.count - 2
        // gridWidth = 2*square + middleCount*letter + (middleCount−1)*keySpacing + 2*g
        let letterGaps = CGFloat(max(0, middleCount - 1)) * keySpacing
        let gap = max(0, (gridWidth - 2 * square - CGFloat(middleCount) * letter - letterGaps) / 2)
        var widths = [CGFloat](repeating: letter, count: keys.count)
        widths[shiftIndex] = keys[shiftIndex].fixedWidth ?? square
        widths[backspaceIndex] = keys[backspaceIndex].fixedWidth ?? square
        var gaps = [CGFloat](repeating: keySpacing, count: max(0, keys.count - 1))
        // 空隙 g 取代 ⇧ 之后、⌫ 之前的默认 keySpacing。
        gaps[shiftIndex] = gap
        if backspaceIndex - 1 >= 0 { gaps[backspaceIndex - 1] = gap }
        return RowLayout(keys: keys, widths: widths, gaps: gaps, sideInset: 0)
    }

    private static func toggleRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        square: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        let specials = keys.indices.filter { keys[$0].action.isToggle || keys[$0].action.isBackspace }
        guard specials.count == 2 else {
            return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: 0, keySpacing: keySpacing)
        }
        var widths = [CGFloat](repeating: 0, count: keys.count)
        var fixedSum: CGFloat = 0
        for i in specials {
            let fixed = keys[i].fixedWidth ?? square
            widths[i] = fixed
            fixedSum += fixed
        }
        let middleCount = keys.count - specials.count
        let middleWidth = middleCount > 0
            ? max(0, (gridWidth - fixedSum - CGFloat(keys.count - 1) * keySpacing) / CGFloat(middleCount))
            : 0
        for i in keys.indices where !specials.contains(i) {
            widths[i] = middleWidth
        }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: 0
        )
    }

    private static func letterRow(
        keys: [KeyDescriptor],
        letter: CGFloat,
        keySpacing: CGFloat,
        sideInset: CGFloat
    ) -> RowLayout {
        let padding: CGFloat
        if keys.count == 10 {
            padding = 0
        } else if keys.count == 9 {
            padding = (letter + keySpacing) / 2
        } else {
            padding = sideInset
        }
        return RowLayout(
            keys: keys,
            widths: Array(repeating: letter, count: keys.count),
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: padding
        )
    }

    private static func weightedRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        sideInset: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        let keyUnit = max(0, gridWidth - sideInset * 2 - CGFloat(keys.count - 1) * keySpacing)
        let totalWeight = keys.reduce(0) { $0 + $1.width }
        // 权重全为 0（异常布局）时避免除零产生 NaN 帧宽，退化为等宽分摊。
        guard totalWeight > 0 else {
            let equalWidth = keys.count > 0 ? keyUnit / CGFloat(keys.count) : 0
            return RowLayout(
                keys: keys,
                widths: [CGFloat](repeating: equalWidth, count: keys.count),
                gaps: [CGFloat](repeating: keySpacing, count: max(0, keys.count - 1)),
                sideInset: sideInset
            )
        }
        let widths = keys.map { keyUnit * $0.width / totalWeight }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: sideInset
        )
    }
}
