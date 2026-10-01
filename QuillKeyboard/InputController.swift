import UIKit
import SwiftUI
import RimeEngine
import Sync
import Models
import KeyboardUI

/// 键盘扩展入口。职责极薄：组合 KeyboardUI + RimeEngine。
final class InputController: UIInputViewController {

    private let rimeContext = RimeContext.shared
    private let inputState = InputState()
    private let sessionID = UUID()
    private var pendingLogExport: UINavigationController?
    private var displayedPreedit: String = ""
    private var hostingController: UIHostingController<KeyboardView>?
    private var doubleSpaceTracker = DoubleSpaceTracker(interval: 0.35)

    /// 最近一次写入视图的键盘类型 / 回车键类型，用于在字段切换时按需刷新。
    private var lastKeyboardType: UIKeyboardType?
    private var lastReturnKeyType: UIReturnKeyType?

    deinit {
        KeyboardDiagnostics.shared.endSession(sessionID.uuidString)
        let rime = rimeContext
        let owner = sessionID
        WebDAVSync.runAfterSync { rime.releaseSession(owner) }
    }

    override func loadView() {
        let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        view = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 只 start() 不部署：全量部署超扩展 ~77MB 内存上限会被 Jetsam 杀死，
        // 数据来自 Bundle 内预构建的 SharedSupport/build。
        rimeContext.claimSession(sessionID)
        KeyboardDiagnostics.shared.beginSession(sessionID.uuidString)
        rimeContext.log("Keyboard: viewDidLoad")
        Task {
            // 已在维护中的进程不重复启动引擎，避免主线程等待后台持有的引擎锁。
            guard !inputState.isSyncing else { return }
            await rimeContext.start()
        }

        createKeyboardView()
    }

    /// 完全访问只影响扩展自身联网（同步）；per-app 自签基线下与主 App 无共享
    /// 通道，状态不回传、UI 不展示，未授权的表象就是同步失败（toast 引导检查设置）。
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshInputTextState()
        refreshKeyboardContext()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetDoubleSpaceState()
        KeyboardDiagnostics.shared.record("键盘显示")
        refreshInputTextState()
        refreshKeyboardContext()
        // viewDidLoad 挂载会有巨大布局位移，须在此挂载；幂等防重复 addChild / 约束累积。
        guard let hostingController, hostingController.view.superview == nil else { return }
        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        view.window?.gestureRecognizers?.forEach { recognizer in
            // 只修改普通手势识别器，避免触碰系统 gate gesture recognizer 产生警告。
            let className = String(describing: type(of: recognizer))
            if !className.contains("System") {
                recognizer.delaysTouchesBegan = false
            }
        }
    }

    /// 读取宿主的键盘类型 / 回车键文案；仅在发生变化时重建 SwiftUI 根视图。
    private func refreshKeyboardContext() {
        let type = textDocumentProxy.keyboardType
        let returnType = textDocumentProxy.returnKeyType
        guard type != lastKeyboardType || returnType != lastReturnKeyType else { return }
        lastKeyboardType = type
        lastReturnKeyType = returnType
        hostingController?.rootView = makeKeyboardView()
    }

    /// 判断输入框是否已有文本（回车键高亮）。部分字段 hasText 不可靠，用上下文兜底。
    private func hasText(in proxy: UITextDocumentProxy) -> Bool {
        if proxy.hasText { return true }
        return !(proxy.documentContextBeforeInput?.isEmpty ?? true)
            || !(proxy.documentContextAfterInput?.isEmpty ?? true)
            || !(proxy.selectedText?.isEmpty ?? true)
    }

    private func refreshInputTextState() {
        inputState.hasInputText = hasText(in: textDocumentProxy)
    }

    private func createKeyboardView() {
        let hostingController = UIHostingController(rootView: makeKeyboardView())
        // 同步页编辑时内容会变高，须把 SwiftUI 尺寸变化传递给系统键盘容器。
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        // UIKit 层全透明，面板背景由系统键盘容器绘制。
        hostingController.view.backgroundColor = .clear
        view.backgroundColor = .clear
        self.hostingController = hostingController
    }

    private func makeKeyboardView() -> KeyboardView {
        KeyboardView(
            rimeContext: rimeContext,
            inputState: inputState,
            keyboardType: textDocumentProxy.keyboardType ?? .default,
            returnKeyType: textDocumentProxy.returnKeyType ?? .default,
            onKey: { [weak self] action in
                self?.handleKeyAction(action)
            },
            onExportLogs: { [weak self] in self?.exportLogs() }
        )
    }

    private func exportLogs() {
        guard let presenter = hostingController,
              presenter.presentedViewController == nil, inputState.logExportHeight == nil else { return }
        do {
            let archive = try KeyboardDiagnostics.shared.export()
            let activity = UIActivityViewController(activityItems: [archive], applicationActivities: nil)
            activity.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in self?.dismissLogExport() }
            )
            let navigation = UINavigationController(rootViewController: activity)
            navigation.modalPresentationStyle = .popover
            navigation.popoverPresentationController?.sourceView = presenter.view
            navigation.popoverPresentationController?.delegate = self
            navigation.popoverPresentationController?.permittedArrowDirections = []
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                Task { @MainActor in self?.dismissLogExport() }
            }
            // 扩展的分享界面只能使用自身区域，导出时临时扩大内在高度。
            let screenHeight = view.window?.windowScene?.effectiveGeometry.coordinateSpace.bounds.height ?? view.bounds.height
            pendingLogExport = navigation
            inputState.logExportHeight = max(view.bounds.height, screenHeight * 0.75)
            view.setNeedsLayout()
        } catch {
            KeyboardDiagnostics.shared.record("日志导出失败：\(error.localizedDescription)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let activity = pendingLogExport else { return }
        guard let height = inputState.logExportHeight else {
            pendingLogExport = nil
            return
        }
        guard view.bounds.height >= height - 1 else { return }
        pendingLogExport = nil
        // 必须等扩展完成自适应布局，否则系统弹出框仍采用原来的键盘高度。
        activity.preferredContentSize = CGSize(width: view.bounds.width, height: height)
        activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 1, height: 1)
        hostingController?.present(activity, animated: true)
    }

    private func dismissLogExport() {
        guard let presenter = hostingController, presenter.presentedViewController != nil else {
            inputState.logExportHeight = nil
            return
        }
        presenter.dismiss(animated: true) { [weak self] in
            self?.inputState.logExportHeight = nil
        }
    }

    private func handleKeyAction(_ action: KeyAction) {
        var handled = false
        var preeditBefore: String = ""
        switch action {
        case .character(let char):
            resetDoubleSpaceState()
            let keyCode = rimeKeyCode(forCharacter: char) ?? 0
            handled = rimeContext.processKey(keyCode)
            // 英文（ascii_mode）下 RIME 不接管纯 ASCII 字符，返回「未处理」，
            // 直接上屏字符本身；有 preedit 时说明仍在组合，不插字。
            if !handled && rimeContext.preedit.isEmpty {
                insertToProxy(char)
                displayedPreedit = ""
            }
        case .composingInput(let text):
            resetDoubleSpaceState()
            handled = rimeContext.appendLiteralInput(text)
        case .directInput(let text):
            if !rimeContext.preedit.isEmpty {
                resetDoubleSpaceState()
                // 组合与后续字符必须作为一次宿主写入，避免跨进程光标更新晚于第二次插入。
                MarkedTextWriter.finishComposition(appending: text, from: rimeContext,
                                                  replacingMarkedText: !displayedPreedit.isEmpty, to: textDocumentProxy)
                inputState.hasInputText = true
                displayedPreedit = ""
                return
            }
            if text == " " {
                if !handleDoubleSpaceAsPeriod(".") {
                    insertToProxy(" ")
                    doubleSpaceTracker.markLiteralSpaceInserted()
                }
                return
            }
            resetDoubleSpaceState()
            insertToProxy(text)
            return
        case .backspace:
            // 退格不消耗一次性大写状态。
            resetDoubleSpaceState()
            // 无拼音 preedit 时无需经过 RIME，直接删字符（更快且避免丢震动）。
            if rimeContext.preedit.isEmpty {
                textDocumentProxy.deleteBackward()
                displayedPreedit = ""
            } else {
                handled = rimeContext.processKey(XK_BackSpace)
                if !handled {
                    textDocumentProxy.deleteBackward()
                    displayedPreedit = ""
                }
            }
        case .space:
            // 空格双语义：组合期交 RIME 选词并复位双击状态；
            // 双击句号只在两次都上屏字面空格时生效。
            if rimeContext.preedit.isEmpty, handleDoubleSpaceAsPeriod("。") {
                return
            }
            // 无拼音 preedit 时跳过 RIME，直接上屏字面空格。
            if rimeContext.preedit.isEmpty {
                insertToProxy(" ")
                doubleSpaceTracker.markLiteralSpaceInserted()
                return
            }
            handled = rimeContext.processKey(XK_space)
            if !handled {
                insertToProxy(" ")
                doubleSpaceTracker.markLiteralSpaceInserted()
            } else {
                // 组合期上屏候选：复位双击状态，让紧随的第二次空格按普通空格处理。
                resetDoubleSpaceState()
            }
        case .startSync:
            resetDoubleSpaceState()
            startManualSync()
            return
        case .return:
            resetDoubleSpaceState()
            // 无拼音 preedit 时跳过 RIME，直接换行。
            if rimeContext.preedit.isEmpty {
                insertToProxy("\n")
                return
            }
            preeditBefore = rimeContext.preedit
            handled = rimeContext.processKey(XK_Return)
        case .selectCandidate(let index):
            resetDoubleSpaceState()
            rimeContext.selectCandidate(at: index)
            handled = true
        case .toggleLanguage:
            resetDoubleSpaceState()
            // ascii_mode 选项由 KeyboardView 在 onKey 返回后写入 RIME。
            commitPendingComposition()
            return
        default:
            resetDoubleSpaceState()
            break
        }

        if handled {
            syncText()
        }

        // Return 回退：如果 RIME 没有产生 commit 且 preedit 仍保留，直接把原始输入上屏。
        if case .return = action,
           !preeditBefore.isEmpty,
           rimeContext.preedit == preeditBefore {
            commitRawPreedit(preeditBefore)
        }
    }

    private func startManualSync() {
        guard rimeContext.preedit.isEmpty else { return }
        resetDoubleSpaceState()
        inputState.sync.start()
    }

    private func commitPendingComposition() {
        guard !rimeContext.preedit.isEmpty else { return }
        MarkedTextWriter.finishComposition(from: rimeContext,
                                          replacingMarkedText: !displayedPreedit.isEmpty, to: textDocumentProxy)
        inputState.hasInputText = true
        displayedPreedit = ""
    }

    /// 直接上屏 preedit 原文并重置 RIME（用于 RIME 未确认/未处理组合的兜底提交）。
    private func commitRawPreedit(_ text: String) {
        commitReplacingMarkedText(text)
        rimeContext.reset()
        displayedPreedit = ""
    }

    /// 双击空格转换为句号：命中判定时回删上一次上屏的字面空格并插入 `periodText`，
    /// 返回 true 表示本次空格已被消费；未命中返回 false，由调用方按空格语义处理。
    private func handleDoubleSpaceAsPeriod(_ periodText: String) -> Bool {
        guard doubleSpaceTracker.isDoubleTap() else { return false }
        if doubleSpaceTracker.lastTapInsertedLiteralSpace {
            textDocumentProxy.deleteBackward()
        }
        insertToProxy(periodText)
        doubleSpaceTracker.reset()
        return true
    }

    /// 本键盘上屏了非空文本，标记输入框已有文本（回车键高亮）。
    private func insertToProxy(_ text: String) {
        textDocumentProxy.insertText(text)
        inputState.hasInputText = true
    }

    private func commitReplacingMarkedText(_ text: String) {
        MarkedTextWriter.commit(text, replacingMarkedText: !displayedPreedit.isEmpty, to: textDocumentProxy)
        inputState.hasInputText = true
    }

    private func resetDoubleSpaceState() {
        doubleSpaceTracker.reset()
    }

    /// 把 RIME 的 commit / preedit 同步进宿主输入框。清空组合必须
    /// `setMarkedText("")` + `unmarkText()`：裸 `unmarkText()` 会固化最后一个字母。
    private func syncText() {
        if let commit = rimeContext.pollCommit(), !commit.isEmpty {
            commitReplacingMarkedText(commit)
            displayedPreedit = ""
        }

        let preedit = rimeContext.preedit
        if preedit != displayedPreedit {
            if preedit.isEmpty {
                textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                textDocumentProxy.unmarkText()
            } else {
                let end = preedit.utf16.count
                textDocumentProxy.setMarkedText(preedit, selectedRange: NSRange(location: end, length: 0))
            }
            displayedPreedit = preedit
        }
    }
}

/// 双击空格 → 句号的状态跟踪。双击句号只在两次都上屏字面空格时生效
/// （组合期第一下是选词、会复位状态），故除时刻外还需记录上次是否字面空格。
private struct DoubleSpaceTracker {
    var lastTap = Date.distantPast
    var lastTapInsertedLiteralSpace = false
    let interval: TimeInterval

    /// 距上次记录的空格按键是否在双击窗口内（不消费状态）。
    func isDoubleTap(_ now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastTap) < interval
    }

    /// 本次空格上屏了字面空格。
    mutating func markLiteralSpaceInserted(_ now: Date = Date()) {
        lastTap = now
        lastTapInsertedLiteralSpace = true
    }

    /// 双击命中后复位（已回删旧空格并插入句号）。
    mutating func reset() {
        lastTap = .distantPast
        lastTapInsertedLiteralSpace = false
    }
}

extension InputController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        inputState.logExportHeight = nil
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        inputState.logExportHeight = nil
    }
}
