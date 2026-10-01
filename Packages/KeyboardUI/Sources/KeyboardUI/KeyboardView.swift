import SwiftUI
import UIKit
import Models
import RimeEngine

public struct KeyboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: KeyboardViewModel
    @State private var candidatesExpanded = false
    @State private var settings = SyncSettingsModel()
    @State private var editorModel = KeyboardViewModel()
    let rimeContext: RimeContext
    let inputState: InputState
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let onKey: (KeyAction) -> Void

    /// 主题跟随宿主 App 的深浅色（同 fcitx5-ios），控制器不解析、由 SwiftUI 环境自动重求值。
    private var resolvedTheme: Theme {
        colorScheme == .dark ? .dark : .light
    }

    public init(
        rimeContext: RimeContext,
        inputState: InputState,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        onKey: @escaping (KeyAction) -> Void
    ) {
        self.rimeContext = rimeContext
        self.inputState = inputState
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.onKey = onKey
        self._viewModel = State(initialValue: KeyboardViewModel())
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
                                isExpanded: $candidatesExpanded, onSelect: selectAndCollapse
                            )
                            keyArea(theme: theme, in: geometry.size.width, model: viewModel)
                        } else {
                            PanelHeader(inputState: inputState, settings: settings, theme: theme)
                            switch inputState.panelMode {
                            case .sync:
                                SyncPanelView(model: settings, inputState: inputState, theme: theme,
                                              onSync: { onKey(.startSync) })
                                if settings.editingField != nil {
                                    keyArea(theme: theme, in: geometry.size.width, model: editorModel, editing: true)
                                }
                            case .log:
                                LogPanelView(theme: theme)
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
        // Toast 的观察限定在悬浮层，避免输入树因提示变化整体刷新。
        .overlay(alignment: .top) {
            SyncToastOverlay(inputState: inputState, theme: theme)
        }
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
        // 展开时一次性补齐全部候选；候选清空的自动收起由子视图自行观察。
        .onChange(of: candidatesExpanded) { _, expanded in
            if expanded {
                rimeContext.loadExpandedCandidates()
            }
        }
    }

    private func panelHeight(theme: Theme) -> CGFloat {
        guard inputState.panelMode == .sync else { return theme.totalHeight }
        return settings.editingField == nil ? 350 : 520
    }

    private func selectAndCollapse(_ index: Int) {
        // 维护进行中不向引擎发送输入，结果提示期间恢复正常输入。
        guard !inputState.isSyncing else { return }
        candidatesExpanded = false
        onKey(.selectCandidate(index))
    }

    /// 键区只依赖低频状态（布局/语言/大小写）；preedit 等高频变化收窄到行视图。
    private func keyArea(theme: Theme, in totalWidth: CGFloat, model: KeyboardViewModel, editing: Bool = false) -> some View {
        VStack(spacing: theme.rowSpacing) {
            if model.currentRows.isEmpty {
                // 布局加载失败兜底：显示错误而非空白键盘。
                // 高度 = 键区高度（总高 − 候选栏 − 上下内边距），与正常键区一致。
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
            // 中/英切换：视图按当前语言把 ascii_mode 写回 RIME。
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
            Button("键盘", systemImage: "keyboard") { inputState.panelMode = .input }
            Button("同步", systemImage: "arrow.triangle.2.circlepath") { inputState.panelMode = .sync }
            Button("日志", systemImage: "doc.text.magnifyingglass") { inputState.panelMode = .log }
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
            PanelMenu(inputState: inputState, theme: theme)
            Text(inputState.panelMode == .sync ? "同步" : "日志")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if settings.editingField != nil {
                Button("完成") { settings.editingField = nil }
                    .buttonStyle(.glass)
                    .font(.system(size: 14, weight: .medium))
            } else {
                Button { inputState.panelMode = .input } label: {
                    Image(systemName: "keyboard").font(.system(size: 14))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("返回键盘")
            }
        }
        .foregroundStyle(theme.keyForeground)
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}

/// 折叠候选栏：在自身 body 观察候选，刷新只重求值本视图。
private struct CandidatesBar: View {
    let rimeContext: RimeContext
    let inputState: InputState
    let theme: Theme
    @Binding var isExpanded: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if rimeContext.preedit.isEmpty || inputState.panelMode != .input {
                PanelMenu(inputState: inputState, theme: theme)
                    .frame(width: 40, height: theme.candidateBarHeight + theme.keyboardPadding.top)
            }
            CandidatePanel(candidates: rimeContext.candidates,
                           highlightedIndex: rimeContext.highlightedCandidateIndex,
                           theme: theme, isExpanded: $isExpanded, onSelect: onSelect)
                .disabled(inputState.isSyncing)
        }
        .onChange(of: rimeContext.candidates.isEmpty) { _, empty in
            if empty { isExpanded = false }
            else { inputState.panelMode = .input }
        }
    }
}

/// 单行键盘行视图：仅含回车键的行读取 preedit / hasInputText，
/// 组合期间只重求值这一行。
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
            ? KeyboardViewModel.effectiveReturnLabel(hasPreedit: hasPreedit, hostLabel: returnKeyLabel)
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
    }

    /// 回车键的动态文案/高亮：有 preedit 显示「⏎」，否则显示宿主文案；
    /// 无 preedit 且输入框有文本时用 `.confirm` 蓝色高亮。其余键原样返回。
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

private struct SyncToastOverlay: View {
    let inputState: InputState
    let theme: Theme

    var body: some View {
        Group {
            if let toast = inputState.toast {
                SyncToastView(toast: toast, theme: theme).padding(.top, 4)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: inputState.toast != nil)
    }
}

/// 同步 toast：候选栏顶部居中的悬浮胶囊。`started` 持续到同步结束被替换，
/// 收起时长由进程级同步状态管理；纯文本无交互，不挡点击。
private struct SyncToastView: View {
    let toast: SyncToast
    let theme: Theme

    var body: some View {
        Text(toast.message)
            .font(.system(size: theme.toastFontSize, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, theme.toastHPadding)
            .padding(.vertical, theme.toastVPadding)
            .background {
                Capsule()
                    .fill(theme.keyBackground)
                    .floatingShadow()
            }
            .allowsHitTesting(false)
    }
}

/// 展开态候选网格：按文本自然宽度分行，首行与折叠候选栏垂直对齐。
/// 只在自身 body 观察候选。
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

    /// 排版与单元格绘制必须基于同一份候选快照，避免 LazyVStack 惰性渲染
    /// 读到被替换的更短数组而越界。
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

        return ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(metrics.rows.indices, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<metrics.rows[row], id: \.self) { col in
                                let index = metrics.rowStarts[row] + col
                                cell(index: index, list: list, minWidth: metrics.minCellWidth)
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

            CandidateChevronButton(
                isExpanded: true,
                height: barHeight,
                theme: theme,
                action: onCollapse
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 网格单元格：自然宽度、左对齐，放不下由分行逻辑换行。
    @ViewBuilder
    private func cell(index: Int, list: [Candidate], minWidth: CGFloat) -> some View {
        // 惰性渲染可能读到被替换的快照，越界下标返回空视图。
        if list.indices.contains(index) {
            let candidate = list[index]
            CandidateCellView(
                text: candidate.text,
                isHighlighted: index == rimeContext.highlightedCandidateIndex,
                theme: theme,
                action: { onSelect(index) }
            )
            .frame(minWidth: minWidth, alignment: .leading)
        } else {
            Color.clear
        }
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
