import Foundation
import UIKit
import Synchronization

enum CandidateGridLayout {
    /// 候选文本会持续变化，缓存必须有上限以控制长会话内存。
    private static let widthCache = Mutex<[String: CGFloat]>([:])
    private static let widthCacheLimit = 512

    /// 测量边距必须与 CandidatePanel 单元格的实际边距一致。
    private static let cellHPadding: CGFloat = 10

    /// 缓存键包含字体名和字号，避免复用不同字体的测量结果。
    static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        let key = "\(font.fontDescriptor.postscriptName)|\(font.pointSize)|\(text)"
        if let width = widthCache.withLock({ $0[key] }) {
            return width
        }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        widthCache.withLock { cache in
            if cache.count >= widthCacheLimit {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = width
        }
        return width
    }

    /// firstRowWidth 为折叠箭头预留首行空间；比较允许 0.5 pt 容差。
    static func rowCounts(
        candidateTexts: [String],
        in width: CGFloat,
        minCellWidth: CGFloat,
        firstRowWidth: CGFloat? = nil,
        font: UIFont
    ) -> [Int] {
        var rows: [Int] = []
        var currentCount = 0
        var currentWidth: CGFloat = 0
        var available = firstRowWidth ?? width
        for text in candidateTexts {
            let itemWidth = max(textWidth(text, font: font) + 2 * cellHPadding, minCellWidth)
            if currentWidth + itemWidth <= available + 0.5 {
                currentWidth += itemWidth
                currentCount += 1
            } else {
                if currentCount > 0 {
                    rows.append(currentCount)
                }
                currentCount = 1
                currentWidth = itemWidth
                available = width
            }
        }
        if currentCount > 0 {
            rows.append(currentCount)
        }
        return rows
    }

    static func rowStartIndices(for rows: [Int]) -> [Int] {
        rows.reduce(into: [0]) { starts, count in
            starts.append(starts[starts.count - 1] + count)
        }
    }

    struct Metrics {
        let rows: [Int]
        let rowStarts: [Int]
        let topInset: CGFloat
        let minCellWidth: CGFloat
    }

    static func measure(
        candidateTexts: [String],
        highlightedIndex: Int,
        in innerWidth: CGFloat,
        chevronWidth: CGFloat,
        font: UIFont,
        barHeight: CGFloat,
        selectionHeight: CGFloat,
        cellHeight: CGFloat
    ) -> Metrics {
        let minCellWidth = (innerWidth - 1) / 6
        // 首行收窄让出折叠箭头位。
        let firstRowWidth = innerWidth - chevronWidth
        let rows = rowCounts(
            candidateTexts: candidateTexts,
            in: innerWidth,
            minCellWidth: minCellWidth,
            firstRowWidth: firstRowWidth,
            font: font
        )
        let rowStarts = rowStartIndices(for: rows)
        let row0Count = rows.first ?? 0
        // 选中 pill 仅在「高亮候选位于首行」时出现；无高亮（-1）或高亮不在首行时首行是普通格。
        let row0Height = (highlightedIndex >= 0 && highlightedIndex < row0Count) ? selectionHeight : cellHeight
        let topInset = max(0, barHeight / 2 - row0Height / 2)
        return Metrics(
            rows: rows,
            rowStarts: rowStarts,
            topInset: topInset,
            minCellWidth: minCellWidth
        )
    }
}
