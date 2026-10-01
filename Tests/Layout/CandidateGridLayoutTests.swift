import Testing
import UIKit
@testable import KeyboardUI

struct CandidateGridLayoutTests {
    private let font = UIFont.systemFont(ofSize: 18)

    @Test("候选自然宽度换行且保留全部索引，首行为箭头让位")
    func wrappingAndIndices() {
        for (width, firstWidth, expected) in [(CGFloat(1000), CGFloat(1000), [5]), (200, 200, [4, 1]), (200, 50, [1, 4]), (50, 50, [1, 1, 1, 1, 1])] {
            let rows = CandidateGridLayout.rowCounts(candidateTexts: Array(repeating: "a", count: 5), in: width, minCellWidth: 50, firstRowWidth: firstWidth, font: font)
            #expect(rows == expected)
            let starts = CandidateGridLayout.rowStartIndices(for: rows)
            #expect(starts.first == 0 && starts.last == 5 && starts.count == rows.count + 1)
        }
        let texts = ["中", "文", "a", "很长很长很长很长很长"]
        let rows = CandidateGridLayout.rowCounts(candidateTexts: texts, in: 120, minCellWidth: 32, font: font)
        #expect(rows.last == 1)
        #expect(CandidateGridLayout.rowStartIndices(for: rows).last == texts.count)
    }

    @Test("文本宽度缓存区分字号与字重")
    func fontCacheIdentity() {
        let text = "缓存字号回归测试 WWW"
        let small = UIFont.systemFont(ofSize: 12)
        let large = UIFont.systemFont(ofSize: 24)
        let bold = UIFont.systemFont(ofSize: 24, weight: .bold)
        #expect(CandidateGridLayout.textWidth(text, font: large) > CandidateGridLayout.textWidth(text, font: small) * 1.9)
        for font in [large, bold] {
            let actual = (text as NSString).size(withAttributes: [.font: font]).width
            #expect(abs(CandidateGridLayout.textWidth(text, font: font) - actual) < 0.01)
        }
    }

    @Test("空网格不产生单元格，首行按普通行高对齐")
    func emptyGrid() {
        let result = measure([], highlighted: 0, width: 320)
        #expect(result.rows.isEmpty && result.rowStarts == [0])
        #expect(result.minCellWidth == (320.0 - 1) / 6)
        #expect(result.topInset == 8)
    }

    @Test("仅首行含选中候选时使用选中行高")
    func firstRowAlignment() {
        for (highlight, inset) in [(0, CGFloat(7)), (1, 8), (-1, 8)] {
            let result = measure(["a", "b"], highlighted: highlight, width: 74)
            #expect(result.rows == [1, 1])
            #expect(result.topInset == inset)
        }
    }

    private func measure(_ texts: [String], highlighted: Int, width: CGFloat) -> CandidateGridLayout.Metrics {
        CandidateGridLayout.measure(candidateTexts: texts, highlightedIndex: highlighted, in: width, chevronWidth: 34, font: font, barHeight: 48, selectionHeight: 34, cellHeight: 32)
    }
}
