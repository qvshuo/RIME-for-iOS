import Foundation
import UIKit
import Synchronization

/// 展开候选网格的纯排版计算：按候选文本测量宽度排满即换行。抽成独立类型便于单元测试。
enum CandidateGridLayout {
    /// 候选文本宽度的进程级缓存（fontSize|text → 宽度）。拼音候选高频重复，
    /// 避免每次展开网格都重新测量同一批文本。上限淘汰：键含完整候选文本，
    /// 长会话会无界累积，而键盘扩展有 ~77MB Jetsam 预算。
    private static let widthCache = Mutex<[String: CGFloat]>([:])
    private static let widthCacheLimit = 512

    /// 行宽测量必须与 `CandidatePanel` 单元格的 `.padding(.horizontal, 10)` 一致。
    private static let cellHPadding: CGFloat = 10

    /// 候选文本的渲染宽度（用与 `candidateFont` 一致的 `UIFont` 测量）。
    /// 缓存键含字体名：同字号不同 weight 的字体宽度不同，只按 pointSize 会串值。
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

    /// 按文本测量宽度把候选排满每行，返回每行候选个数。长词自动减每行个数。
    /// `firstRowWidth` 让首行收窄避让折叠箭头；宽度比较带 0.5pt 浮点容差。
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

    /// 展开网格的排版结果：每行候选数、行首下标前缀和、首行上边距与最小格宽。
    struct Metrics {
        let rows: [Int]
        let rowStarts: [Int]
        let topInset: CGFloat
        let minCellWidth: CGFloat
    }

    /// 一次性算好展开网格排版。首行中心对齐折叠候选栏（barHeight/2），顶边距按
    /// 首行实际行高（选中 pill 是 selectionHeight、普通格是 cellHeight）计算；
    /// minCellWidth 比 innerWidth/6 略小，保证 6 个最小格恰好排满（浮点容差）。
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
