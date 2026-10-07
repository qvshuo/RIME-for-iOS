import SwiftUI
import UIKit
import KeyboardModels
import RimeEngine

public struct KeyboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: KeyboardInputModel
    @State private var candidatesExpanded = false
    @State private var settings = SyncSettingsModel()
    @State private var editorModel = KeyboardInputModel()
    let rimeContext: RimeContext
    let inputState: InputState
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let hasFullAccess: () -> Bool
    let onKey: (KeyAction) -> Void
    let onExportLogs: () -> Void

    private var resolvedTheme: Theme {
        colorScheme == .dark ? .dark : .light
    }

    public init(
        rimeContext: RimeContext,
        inputState: InputState,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        hasFullAccess: @escaping () -> Bool = { true },
        onKey: @escaping (KeyAction) -> Void,
        onExportLogs: @escaping () -> Void = {}
    ) {
        self.rimeContext = rimeContext
        self.inputState = inputState
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.hasFullAccess = hasFullAccess
        self.onKey = onKey
        self.onExportLogs = onExportLogs
        self._viewModel = State(initialValue: KeyboardInputModel())
    }

    public var body: some View {
        let theme = resolvedTheme
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 面板透明，由系统键盘容器绘制背景。
                Color.black.opacity(0.001)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if candidatesExpanded {
                        // 展开态网格覆盖整个键盘，避免与折叠候选栏首词重复。
                        ExpandedCandidateGrid(
                            rimeContext: rimeContext,
                            theme: theme,
                            totalWidth: geometry.size.width,
                            onCollapse: { candidatesExpanded = false },
                            onSelect: selectAndCollapse
                        )
                        .transition(.opacity)
                    } else {
                        if inputState.panelMode == .input {
                            CandidatesBar(
                                rimeContext: rimeContext, inputState: inputState, theme: theme,
                                isExpanded: Binding(get: { candidatesExpanded }, set: { expanded in
                                    if expanded { rimeContext.loadExpandedCandidates() }
                                    candidatesExpanded = expanded
                                }), onSelect: selectAndCollapse
                            )
                            keyArea(theme: theme, in: geometry.size.width, model: viewModel)
                        } else {
                            PanelHeader(inputState: inputState, settings: settings, theme: theme)
                            switch inputState.panelMode {
                            case .sync:
                                SyncPanelView(model: settings, inputState: inputState, theme: theme,
                                              hasFullAccess: hasFullAccess, onSync: { onKey(.startSync) })
                                if settings.editingField != nil {
                                    keyArea(theme: theme, in: geometry.size.width, model: editorModel, editing: true)
                                }
                            case .log:
                                LogPanelView(isVisible: inputState.isVisible, theme: theme, onExport: onExportLogs)
                            case .input:
                                EmptyView()
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.1), value: candidatesExpanded)
        }
        // 用主题总高度作 SwiftUI 内在尺寸，系统键盘容器按此高度平滑滑入。
        .frame(height: panelHeight(theme: theme))
        .frame(maxWidth: .infinity)
        .onAppear {
            KeyboardFeedback.prepare()
            viewModel.handleKeyboardTypeChange(keyboardType)
            viewModel.handleReturnKeyType(returnKeyType)
            if !inputState.isSyncing { rimeContext.setAsciiMode(viewModel.inputLanguage == .english) }
        }
        .onChange(of: keyboardType) { _, newType in
            viewModel.handleKeyboardTypeChange(newType)
            if !inputState.isSyncing { rimeContext.setAsciiMode(viewModel.inputLanguage == .english) }
        }
        .onChange(of: returnKeyType) { _, newType in
            viewModel.handleReturnKeyType(newType)
        }
        .onChange(of: inputState.isSyncing) { _, syncing in
            if !syncing { rimeContext.setAsciiMode(viewModel.inputLanguage == .english) }
        }
        .onChange(of: settings.editingField) { old, new in
            if old == nil, new != nil {
                editorModel.handleKeyboardTypeChange(.asciiCapable)
                editorModel.currentLayout = .qwerty
                editorModel.shiftState = .lowercase
            }
        }
        .onChange(of: inputState.panelMode) { _, mode in
            settings.editingField = nil
            let name = switch mode { case .input: "输入"; case .sync: "同步"; case .log: "日志" }
            KeyboardDiagnostics.shared.record("面板 → \(name)")
        }
    }

    private func panelHeight(theme: Theme) -> CGFloat {
        switch inputState.panelMode {
        case .input: theme.totalHeight
        case .sync: settings.editingField == nil ? 480 : 580
        case .log: 480
        }
    }

    private func selectAndCollapse(_ index: Int) {
        // 维护进行中不向引擎发送输入，结果提示期间恢复正常输入。
        guard !inputState.isSyncing else { return }
        candidatesExpanded = false
        onKey(.selectCandidate(index))
    }

    /// 高频组合状态由行视图观察，避免每次按键重建整个键区。
    private func keyArea(theme: Theme, in totalWidth: CGFloat, model: KeyboardInputModel, editing: Bool = false) -> some View {
        VStack(spacing: theme.rowSpacing) {
            if model.currentRows.isEmpty {
                // 失败提示占用同样的键区高度，避免系统键盘容器跳变。
                let keysAreaHeight = theme.totalHeight
                    - theme.candidateBarHeight
                    - theme.keyboardPadding.top
                    - theme.keyboardPadding.bottom
                VStack(spacing: 8) {
                    Text("键盘布局加载失败")
                        .font(theme.candidateFont)
                        .foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: keysAreaHeight)
            } else {
                // 行顺序固定，用下标做稳定身份，避免重建导致 @State 丢失与视图抖动。
                ForEach(Array(model.currentRows.enumerated()), id: \.offset) { _, row in
                    KeyboardRowView(
                        row: row,
                        theme: theme,
                        totalWidth: totalWidth,
                        shiftState: model.shiftState,
                        returnKeyLabel: editing ? "下一项" : model.returnKeyLabel,
                        rimeContext: rimeContext,
                        inputState: inputState,
                        editingCredentials: editing,
                        onKey: handleKey
                    )
                }
            }
        }
        .padding(
            EdgeInsets(
                top: 0,
                leading: theme.keyboardPadding.leading,
                bottom: theme.keyboardPadding.bottom,
                trailing: theme.keyboardPadding.trailing
            )
        )
    }

    private func handleKey(_ action: KeyAction) {
        guard !inputState.isSyncing else { return }
        if settings.editingField != nil {
            if action == .toggleLanguage { settings.append("@"); return }
            if let transformed = editorModel.consume(action) { settings.consume(transformed) }
            return
        }
        if let transformed = viewModel.consume(action, rimeContext: rimeContext) {
            onKey(transformed)
            if case .toggleLanguage = transformed {
                if !inputState.isSyncing { rimeContext.setAsciiMode(viewModel.inputLanguage == .english) }
            }
        }
    }
}

private struct PanelMenu: View {
    let inputState: InputState
    let theme: Theme

    var body: some View {
        Menu {
            Button("同步", systemImage: "arrow.triangle.2.circlepath") { inputState.panelMode = .sync }
                .accessibilityIdentifier("panel-menu-sync")
            Button("日志", systemImage: "doc.text.magnifyingglass") { inputState.panelMode = .log }
                .accessibilityIdentifier("panel-menu-log")
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.keyForeground)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("功能菜单")
    }
}

private struct PanelHeader: View {
    let inputState: InputState
    let settings: SyncSettingsModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            Button { inputState.panelMode = .input } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.keyForeground)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回键盘")
            .accessibilityIdentifier("panel-back-input")
            Text(inputState.panelMode == .sync ? "同步" : "日志")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if settings.editingField != nil {
                Button("完成") { settings.editingField = nil }
                    .buttonStyle(.glass)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .foregroundStyle(theme.keyForeground)
        .padding(.horizontal, theme.keyboardPadding.leading)
        .frame(height: 48)
    }
}

private struct CandidatesBar: View {
    let rimeContext: RimeContext
    let inputState: InputState
    let theme: Theme
    @Binding var isExpanded: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if rimeContext.preedit.isEmpty {
                PanelMenu(inputState: inputState, theme: theme)
                    .padding(.leading, theme.keyboardPadding.leading)
                    .frame(width: theme.keyboardPadding.leading + 40,
                           height: theme.candidateBarHeight + theme.keyboardPadding.top, alignment: .leading)
            }
            CandidatePanel(candidates: rimeContext.candidates,
                           highlightedIndex: rimeContext.highlightedCandidateIndex,
                           theme: theme, isExpanded: $isExpanded, onSelect: onSelect)
                .disabled(inputState.isSyncing)
        }
        .onChange(of: rimeContext.candidates.isEmpty) { _, empty in
            if empty { isExpanded = false }
        }
    }
}

/// 只有含回车键的行观察 preedit 和 hasInputText。
private struct KeyboardRowView: View {
    let row: RowDescriptor
    let theme: Theme
    let totalWidth: CGFloat
    let shiftState: ShiftState
    let returnKeyLabel: String
    let rimeContext: RimeContext
    let inputState: InputState
    let editingCredentials: Bool
    let onKey: (KeyAction) -> Void

    var body: some View {
        // 三元条件短路保证不含回车键的行不读取 preedit / hasInputText（不被追踪）。
        let hasReturn = row.keys.contains { $0.action.isReturn }
        let hasPreedit = hasReturn && !editingCredentials ? !rimeContext.preedit.isEmpty : false
        let highlightReturn = hasReturn ? (!hasPreedit && (editingCredentials || inputState.hasInputText)) : false
        let effectiveReturnLabel = hasReturn
            ? KeyboardInputModel.effectiveReturnLabel(hasPreedit: hasPreedit, hostLabel: returnKeyLabel)
            : nil

        let layout = RowLayoutMath.layout(RowLayoutParameters(
            keys: row.keys,
            totalWidth: totalWidth,
            sideInset: row.leadingPadding,
            keyboardLeading: theme.keyboardPadding.leading,
            keyboardTrailing: theme.keyboardPadding.trailing,
            keySpacing: theme.keySpacing,
            keyHeight: theme.keyHeight,
            minSpaceWidth: theme.keyHeight * 2.0,
            returnLabelWidth: hasReturn
                ? ReturnLabelWidth.measure(effectiveReturnLabel ?? returnKeyLabel, fontSize: theme.specialKeyFontSize)
                : 0
        ))

        return HStack(spacing: 0) {
                // 键位固定，用下标做稳定身份；行间距由 gaps 决定（见 RowLayoutMath）。
                ForEach(Array(layout.keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Spacer()
                            .frame(width: layout.gaps[index - 1])
                    }
                    Key(
                        descriptor: effectiveDescriptor(
                            for: key,
                            hasReturn: hasReturn,
                            effectiveReturnLabel: effectiveReturnLabel,
                            highlightReturn: highlightReturn
                        ),
                        theme: theme,
                        shiftState: shiftState,
                        action: onKey
                    )
                    .frame(
                        width: layout.widths[index],
                        height: theme.keyHeight
                    )
                }
        }
        .padding(.horizontal, layout.sideInset)
        // 布局切换同时改变键宽与内容，几何变化必须即时完成。
        .transaction { $0.animation = nil }
    }

    private func effectiveDescriptor(
        for key: KeyDescriptor,
        hasReturn: Bool,
        effectiveReturnLabel: String?,
        highlightReturn: Bool
    ) -> KeyDescriptor {
        if editingCredentials, key.action == .toggleLanguage { return key.with(label: "@") }
        guard hasReturn, key.action.isReturn else { return key }
        return key.with(label: effectiveReturnLabel ?? key.label, style: highlightReturn ? .confirm : key.style)
    }
}

private struct ExpandedCandidateGrid: View {
    let rimeContext: RimeContext
    let theme: Theme
    let totalWidth: CGFloat
    let onCollapse: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        grid
            // 候选为空时自动收起，避免空网格挡住键盘。
            .onChange(of: rimeContext.candidates.isEmpty) { _, empty in
                if empty { onCollapse() }
            }
    }

    /// 惰性单元格必须使用排版时的候选快照，避免数组替换后下标越界。
    private var grid: some View {
        let barHeight = theme.candidateBarHeight + theme.keyboardPadding.top
        let gridPadding: CGFloat = theme.keyboardPadding.leading
        let chevronWidth = theme.chevronWidth
        let list = rimeContext.candidates
        let innerWidth = totalWidth - gridPadding * 2
        let metrics = CandidateGridLayout.measure(
            candidateTexts: list.map(\.text),
            highlightedIndex: rimeContext.highlightedCandidateIndex,
            in: innerWidth,
            chevronWidth: chevronWidth,
            font: UIFont.systemFont(ofSize: theme.candidateCellFontSize),
            barHeight: barHeight,
            selectionHeight: theme.candidateSelectionHeight,
            cellHeight: theme.candidateCellHeight
        )

        // 将每行候选切片为独立值；惰性闭包不再使用可变化的行号索引排版数组。
        let rows = metrics.rows.enumerated().map { row, count in
            let start = metrics.rowStarts[row]
            return Array(list.enumerated().dropFirst(start).prefix(count))
        }
        return ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { row, items in
                        HStack(spacing: 0) {
                            ForEach(items, id: \.offset) { index, candidate in
                                CandidateCellView(
                                    text: candidate.text,
                                    isHighlighted: index == rimeContext.highlightedCandidateIndex,
                                    theme: theme,
                                    action: { onSelect(index) }
                                )
                                .frame(minWidth: metrics.minCellWidth, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, row == 0 ? chevronWidth : 0)
                    }
                }
                .padding(.leading, gridPadding)
                .padding(.trailing, gridPadding)
                .padding(.bottom, gridPadding)
                .padding(.top, metrics.topInset)
            }
            .scrollEdgeEffectHidden(true, for: .all)

            CandidateChevronButton(
                isExpanded: true,
                height: barHeight,
                theme: theme,
                action: onCollapse
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Light Keyboard") {
    KeyboardView(
        rimeContext: RimeContext.shared,
        inputState: InputState(),
        onKey: { action in
            print("key: \(action)")
        }
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Keyboard") {
    KeyboardView(
        rimeContext: RimeContext.shared,
        inputState: InputState(),
        onKey: { action in
            print("key: \(action)")
        }
    )
    .preferredColorScheme(.dark)
}
