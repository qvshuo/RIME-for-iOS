import Testing
import UIKit
@testable import KeyboardUI

/// 展开候选网格排版计算的纯逻辑测试。
struct CandidateGridLayoutTests {
    private let font = UIFont.systemFont(ofSize: 18)

    @Test("rowStartIndices 是行数前缀和")
    func rowStartIndicesArePrefixSums() {
        #expect(CandidateGridLayout.rowStartIndices(for: []) == [0])
        #expect(CandidateGridLayout.rowStartIndices(for: [3, 2, 1]) == [0, 3, 5, 6])
        #expect(CandidateGridLayout.rowStartIndices(for: [1, 1, 1, 1]) == [0, 1, 2, 3, 4])
    }

    @Test("宽度足够时所有候选排在一行")
    func rowCountsFitsAllInOneRow() {
        let rows = CandidateGridLayout.rowCounts(
            candidateTexts: ["a", "b", "c"],
            in: 1000,
            minCellWidth: 20,
            font: font
        )
        #expect(rows == [3])
    }

    @Test("最小格宽决定每行一个时逐候选换行")
    func rowCountsWrapsEveryItemWhenTight() {
        // minCellWidth 30 远大于可用宽度，每个候选各占一行。
        let rows = CandidateGridLayout.rowCounts(
            candidateTexts: Array(repeating: "中", count: 6),
            in: 50,
            minCellWidth: 30,
            font: font
        )
        #expect(rows == [1, 1, 1, 1, 1, 1])
    }

    @Test("firstRowWidth 让首行提前换行")
    func rowCountsHonorsFirstRowWidth() {
        let texts = Array(repeating: "a", count: 5)
        let normal = CandidateGridLayout.rowCounts(
            candidateTexts: texts,
            in: 200,
            minCellWidth: 50,
            font: font
        )
        #expect(normal == [4, 1])

        let narrowed = CandidateGridLayout.rowCounts(
            candidateTexts: texts,
            in: 200,
            minCellWidth: 50,
            firstRowWidth: 50,
            font: font
        )
        #expect(narrowed == [1, 4])
    }

    @Test("行起始下标与候选总数一致")
    func rowStartsCoverAllCandidates() {
        let texts = ["中", "文", "a", "b", "c", "很长很长很长很长很长"]
        let rows = CandidateGridLayout.rowCounts(
            candidateTexts: texts,
            in: 320,
            minCellWidth: 32,
            font: font
        )
        let starts = CandidateGridLayout.rowStartIndices(for: rows)
        #expect(starts.first == 0)
        #expect(starts.last == texts.count)
        #expect(starts.count == rows.count + 1)
    }

    @Test("同一字体不同字号不会复用错误的宽度")
    func textWidthIncludesFontSize() {
        let text = "缓存字号回归测试"
        let small = CandidateGridLayout.textWidth(text, font: .systemFont(ofSize: 12))
        let large = CandidateGridLayout.textWidth(text, font: .systemFont(ofSize: 24))
        #expect(large > small * 1.9)
    }

    @Test("textWidth 对常规文本返回正宽度")
    func textWidthIsPositive() {
        #expect(CandidateGridLayout.textWidth("中文", font: font) > 0)
        #expect(CandidateGridLayout.textWidth("", font: font) >= 0)
    }

    @Test("measure 空候选给出空排版与 minCellWidth")
    func measureEmpty() {
        let m = CandidateGridLayout.measure(
            candidateTexts: [],
            highlightedIndex: 0,
            in: 320,
            chevronWidth: 34,
            font: font,
            barHeight: 48,
            selectionHeight: 34,
            cellHeight: 32
        )
        #expect(m.rows.isEmpty)
        #expect(m.rowStarts == [0])
        #expect(m.minCellWidth == (320.0 - 1) / 6)
        // 空网格按普通格高对齐：48/2 − 32/2 = 8。
        #expect(m.topInset == 8.0)
    }

    @Test("measure 首行含选中 pill 时顶边距按 34 高")
    func measureTopInsetUsesSelectionHeightWhenHighlightedInFirstRow() {
        let m = CandidateGridLayout.measure(
            candidateTexts: ["很长很长很长很长很长"],
            highlightedIndex: 0,
            in: 100,
            chevronWidth: 34,
            font: font,
            barHeight: 48,
            selectionHeight: 34,
            cellHeight: 32
        )
        #expect(m.rows == [1])
        // 选中格在首行，行高 34：48/2 − 34/2 = 7。
        #expect(m.topInset == 7.0)
    }

    @Test("measure 首行不含选中格时顶边距按普通格高")
    func measureTopInsetUsesCellHeightWhenHighlightNotInFirstRow() {
        // 首行可用宽 74 − chevron 34 = 40，只放得下单个候选格（"a" ≈ 29.5），
        // "b" 换行到第二行，高亮候选（下标 1）不在首行 → 顶边距按普通格高（32）计算。
        let m = CandidateGridLayout.measure(
            candidateTexts: ["a", "b"],
            highlightedIndex: 1,
            in: 74,
            chevronWidth: 34,
            font: font,
            barHeight: 48,
            selectionHeight: 34,
            cellHeight: 32
        )
        #expect(m.rows == [1, 1])
        // 首行不含选中格，行高 32：48/2 − 32/2 = 8。
        #expect(m.topInset == 8.0)
    }

    @Test("measure 无高亮候选（-1）时首行按普通格高")
    func measureTopInsetUsesCellHeightWhenNoHighlight() {
        let m = CandidateGridLayout.measure(
            candidateTexts: ["a", "b"],
            highlightedIndex: -1,
            in: 74,
            chevronWidth: 34,
            font: font,
            barHeight: 48,
            selectionHeight: 34,
            cellHeight: 32
        )
        #expect(m.rows == [1, 1])
        // 无高亮时首行是普通格：48/2 − 32/2 = 8。
        #expect(m.topInset == 8.0)
    }
}
