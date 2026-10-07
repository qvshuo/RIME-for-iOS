import UIKit
import SwiftUI
import RimeEngine
import RimeSync
import KeyboardModels
import KeyboardUI

final class KeyboardInputController: UIInputViewController {
    private let rimeContext = RimeContext.shared
    private let inputState = InputState()
    private let sessionID = UUID()
    private var documentID: UUID?
    private var needsDocumentReset = false
    private var displayedPreedit: String = ""
    private var hostingController: UIHostingController<KeyboardView>?
    private var doubleSpaceTracker = DoubleSpaceTracker(interval: 0.35)

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

        // 扩展只加载预构建数据，全量部署可能超过进程内存预算。
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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshDocumentState()
        refreshInputTextState()
        refreshKeyboardContext()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputState.isVisible = true
        resetDoubleSpaceState()
        KeyboardDiagnostics.shared.record("键盘显示")
        refreshDocumentState()
        refreshInputTextState()
        refreshKeyboardContext()
        // 即将显示时再挂载，避免键盘滑入过程中因宿主尺寸更新而跳动。
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputState.isVisible = false
        KeyboardDiagnostics.shared.record("键盘隐藏")
        resetDoubleSpaceState()
    }

    /// 切换输入框时，UIKit 可能返回 nil；将其视作身份变化，不能拒绝后续输入。
    private func refreshDocumentState() {
        let proxy = textDocumentProxy as? NSObject
        let current = proxy?.value(forKey: "documentIdentifier") as? UUID
        if documentID != current {
            needsDocumentReset = true
            displayedPreedit = ""
            resetDoubleSpaceState()
        }
        documentID = current
        // 维护持有引擎锁时不阻塞主线程；恢复输入前再丢弃旧输入框的组合。
        if needsDocumentReset, !inputState.isSyncing {
            rimeContext.reset()
            needsDocumentReset = false
        }
    }

    private func refreshKeyboardContext() {
        let type = textDocumentProxy.keyboardType
        let returnType = textDocumentProxy.returnKeyType
        guard type != lastKeyboardType || returnType != lastReturnKeyType else { return }
        lastKeyboardType = type
        lastReturnKeyType = returnType
        hostingController?.rootView = makeKeyboardView()
    }

    /// 部分宿主的 hasText 不可靠，需要用可见上下文兜底。
    private func hasText(in proxy: UITextDocumentProxy) -> Bool {
        if proxy.hasText { return true }
        return !(proxy.documentContextBeforeInput?.isEmpty ?? true)
            || !(proxy.documentContextAfterInput?.isEmpty ?? true)
            || !(proxy.selectedText?.isEmpty ?? true)
    }

    private func refreshInputTextState() {
        let hasText = hasText(in: textDocumentProxy)
        if inputState.hasInputText != hasText { inputState.hasInputText = hasText }
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
            hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
            onKey: { [weak self] action in
                self?.handleKeyAction(action)
            },
            onExportLogs: { [weak self] in self?.exportLogs() }
        )
    }

    private func exportLogs() {
        guard let presenter = hostingController,
              presenter.presentedViewController == nil else { return }
        do {
            let archive = try KeyboardDiagnostics.shared.export()
            let activity = UIActivityViewController(activityItems: [archive], applicationActivities: nil)
            activity.modalPresentationStyle = .popover
            activity.popoverPresentationController?.sourceView = presenter.view
            activity.popoverPresentationController?.delegate = self
            activity.popoverPresentationController?.permittedArrowDirections = []
            // 分享面板沿用日志页尺寸，不改变系统键盘容器的高度。
            activity.preferredContentSize = presenter.view.bounds.size
            activity.popoverPresentationController?.sourceRect = CGRect(
                x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 1, height: 1
            )
            presenter.present(activity, animated: true)
        } catch {
            KeyboardDiagnostics.shared.record("日志导出失败：\(error.localizedDescription)")
        }
    }

    private func handleKeyAction(_ action: KeyAction) {
        guard inputState.isVisible else { return }
        refreshDocumentState()
        var handled = false
        var preeditBefore: String = ""
        switch action {
        case .character(let char):
            resetDoubleSpaceState()
            let keyCode = rimeKeyCode(forCharacter: char) ?? 0
            handled = rimeContext.processKey(keyCode)
            // 未处理的英文字符直接上屏；仍有组合时不能重复插入。
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
            resetDoubleSpaceState()
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
            // 候选提交不参与双空格句号判定。
            if rimeContext.preedit.isEmpty, handleDoubleSpaceAsPeriod("。") {
                return
            }
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
                resetDoubleSpaceState()
            }
        case .startSync:
            resetDoubleSpaceState()
            startManualSync()
            return
        case .return:
            resetDoubleSpaceState()
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
        guard hasFullAccess, rimeContext.preedit.isEmpty else { return }
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

    private func commitRawPreedit(_ text: String) {
        commitReplacingMarkedText(text)
        rimeContext.reset()
        displayedPreedit = ""
    }

    private func handleDoubleSpaceAsPeriod(_ periodText: String) -> Bool {
        guard doubleSpaceTracker.isDoubleTap() else { return false }
        if doubleSpaceTracker.lastTapInsertedLiteralSpace {
            textDocumentProxy.deleteBackward()
        }
        insertToProxy(periodText)
        doubleSpaceTracker.reset()
        return true
    }

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

    /// 清空 marked text 后再 unmark；直接 unmark 会提交最后一个字母。
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

/// 只有两次字面空格才参与双击句号；候选提交必须复位计时。
private struct DoubleSpaceTracker {
    var lastTap = Date.distantPast
    var lastTapInsertedLiteralSpace = false
    let interval: TimeInterval

    func isDoubleTap(_ now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastTap) < interval
    }

    mutating func markLiteralSpaceInserted(_ now: Date = Date()) {
        lastTap = now
        lastTapInsertedLiteralSpace = true
    }

    mutating func reset() {
        lastTap = .distantPast
        lastTapInsertedLiteralSpace = false
    }
}

extension KeyboardInputController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}
