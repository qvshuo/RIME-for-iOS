import SwiftUI
import KeyboardModels

public struct CandidatePanel: View {
    let candidates: [Candidate]
    let highlightedIndex: Int
    let theme: Theme
    @Binding var isExpanded: Bool
    let onSelect: (Int) -> Void

    private var barHeight: CGFloat {
        theme.candidateBarHeight + theme.keyboardPadding.top
    }

    public init(
        candidates: [Candidate],
        highlightedIndex: Int,
        theme: Theme,
        isExpanded: Binding<Bool>,
        onSelect: @escaping (Int) -> Void
    ) {
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.theme = theme
        _isExpanded = isExpanded
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        // 候选文本每次敲键都变，用下标做稳定身份避免整组重建。
                        ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                            candidateButton(index: index, candidate: candidate)
                        }
                    }
                    .padding(.leading, theme.keyboardPadding.leading)
                    .frame(height: geometry.size.height, alignment: .center)
                }
                // 系统滚动边缘效果会模糊候选文字，候选区必须保持清晰。
                .scrollEdgeEffectHidden(true, for: .all)
            }

            if !candidates.isEmpty {
                expandToggle
            }
        }
        .frame(height: barHeight)
    }

    private var expandToggle: some View {
        CandidateChevronButton(
            isExpanded: isExpanded,
            height: barHeight,
            theme: theme,
            action: { isExpanded.toggle() }
        )
    }

    private func candidateButton(index: Int, candidate: Candidate) -> some View {
        let isSelected = index == highlightedIndex
        return CandidateCellView(
            text: candidate.text,
            isHighlighted: isSelected,
            theme: theme,
            action: { onSelect(index) }
        )
        .frame(height: barHeight, alignment: .center)
    }
}

struct CandidateCellView: View {
    let text: String
    let isHighlighted: Bool
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(theme.candidateFont)
                .foregroundStyle(.primary)
                .padding(.horizontal, isHighlighted ? theme.candidateSelectionHPadding : 10)
                .frame(height: isHighlighted ? theme.candidateSelectionHeight : theme.candidateCellHeight)
                .background {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: theme.candidateSelectionCornerRadius, style: .continuous)
                            .fill(theme.candidateSelectionFill)
                    }
                }
        }
        .buttonStyle(CandidateFeedbackButtonStyle())
        .accessibilityLabel(text)
        .accessibilityHint("上屏")
    }
}

struct CandidateChevronButton: View {
    let isExpanded: Bool
    let height: CGFloat
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: theme.chevronIconFontSize, weight: .medium))
                .foregroundStyle(Color(hex: 0x4D5650))
                .frame(width: theme.chevronWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "收起候选" : "展开候选")
    }
}

struct CandidateFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    KeyboardFeedback.play()
                }
            }
    }
}
