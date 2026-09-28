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
    private var displayedPreedit: String = ""
    private var hostingController: UIHostingController<KeyboardView>?
    private var doubleSpaceTracker = DoubleSpaceTracker(interval: 0.35)

    /// 最近一次写入视图的键盘类型 / 回车键类型，用于在字段切换时按需刷新。
    private var lastKeyboardType: UIKeyboardType?
    private var lastReturnKeyType: UIReturnKeyType?

    /// 手动同步（同步页按钮触发）是否进行中，防止重复触发。
    private var isSyncing = false

    /// `.completed / .failed` toast 的自动收起任务。
    private var toastDismissTask: Task<Void, Never>?

    /// 面板模式观察任务：候选出现时强制切回输入页。
    private var panelWatchTask: Task<Void, Never>?

    /// 本次启动是否检测到上次键盘异常退出（闪退/Jetsam 标记）。
    private var crashedLastRun = false

    deinit {
        panelWatchTask?.cancel()
        toastDismissTask?.cancel()
        // 走到 deinit = 正常退出，清除崩溃标记（闪退/Jetsam 不会走这里）。
        rimeContext.recordKeyboardExit()
        rimeContext.destroySession()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 崩溃检测：上次标记还在 = 上次未走 deinit（闪退/Jetsam）。
        // SIGSEGV 等信号到达时进程已无安全执行环境，写文件不可靠，改用
        // 「启动写入 / deinit 清除」标记法，下次启动补记崩溃日志。
        crashedLastRun = rimeContext.recordKeyboardLaunch()
        installCrashHandlers()

        // 只 start() 不部署：全量部署超扩展 ~77MB 内存上限会被 Jetsam 杀死，
        // 数据来自 Bundle 内预构建的 SharedSupport/build。
        rimeContext.log("Keyboard: viewDidLoad")
        rimeContext.keyboardLog("viewDidLoad\(crashedLastRun ? "（上次异常退出）" : "")")
        Task {
            await rimeContext.start()
            rimeContext.keyboardLog("RIME start 完成")
        }

        createKeyboardView()
        startPanelWatch()
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
        rimeContext.keyboardLog("viewWillAppear")
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
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        // UIKit 层全透明，面板背景由系统键盘容器绘制。
        hostingController.view.backgroundColor = .clear
        view.backgroundColor = .clear
        self.hostingController = hostingController
    }

    private func makeKeyboardView() -> KeyboardView {
        var view = KeyboardView(
            rimeContext: rimeContext,
            inputState: inputState,
            keyboardType: textDocumentProxy.keyboardType ?? .default,
            returnKeyType: textDocumentProxy.returnKeyType ?? .default,
            onKey: { [weak self] action in
                self?.handleKeyAction(action)
            }
        )
        view.onSync = { [weak self] in
            self?.startManualSync()
        }
        view.isSyncing = isSyncing
        view.crashedLastRun = crashedLastRun
        return view
    }

    /// 面板模式守卫：候选出现时强制切回输入页（功能页不挡候选）；
    /// 面板切换写入键盘日志节点。
    private func startPanelWatch() {
        let state = inputState
        let rime = rimeContext
        panelWatchTask = Task { [weak self, weak state, weak rime] in
            var lastMode = state?.panelMode
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let state, let rime else { return }
                let mode = state.panelMode
                if mode != lastMode {
                    let name: String = switch mode {
                    case .input: "输入"
                    case .sync: "同步"
                    case .log: "日志"
                    }
                    rime.keyboardLog("面板 → \(name)")
                    lastMode = mode
                }
                // 候选出现且不在输入页：切回输入页，候选优先。
                if mode != .input, !(self?.rimeContext.candidates.isEmpty ?? true) {
                    state.panelMode = .input
                }
            }
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
        case .directInput(let text):
            if text == " " {
                if !handleDoubleSpaceAsPeriod(".") {
                    insertToProxy(" ")
                    doubleSpaceTracker.markLiteralSpaceInserted()
                }
                return
            }
            resetDoubleSpaceState()
            commitPendingComposition()
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
        case .clearLogs:
            resetDoubleSpaceState()
            clearKeyboardLogs()
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

    /// 同步页按钮触发的手动同步；完成后按需重建会话让合并的新词生效。
    private func startManualSync() {
        guard !isSyncing else { return }
        // 有组合时不开始：打断会丢 preedit / 候选。
        guard rimeContext.preedit.isEmpty else { return }
        isSyncing = true
        toastDismissTask?.cancel()
        inputState.toast = .started
        // toast 变化驱动 SwiftUI 重求值 body，使同步页按钮进入「同步中…」。
        hostingController?.rootView = makeKeyboardView()
        rimeContext.log("Keyboard: manual WebDAV sync (panel button)")
        rimeContext.keyboardLog("手动同步开始")
        let rime = rimeContext
        // 弱引用：键盘收起时不应把控制器保留到同步结束（最坏 15s+）。
        Task { [weak self] in
            let success = await WebDAVSync.syncWithTimeout(.seconds(60))
            rime.log("Keyboard: manual WebDAV sync done success=\(success)")
            rime.keyboardLog("手动同步结束 success=\(success)")
            await MainActor.run {
                guard let self else { return }
                if self.rimeContext.preedit.isEmpty {
                    // 在同步专用串行队列重建：僵尸同步可能持引擎锁，主线程调用会阻塞到它结束。
                    // 捕获 context 单例而非 self，避免闭包强持有控制器。
                    let rimeForRecreate = self.rimeContext
                    WebDAVSync.runAfterSync {
                        rimeForRecreate.recreateSession()
                    }
                }
                let toast: SyncToast = success ? .completed : .failed
                self.inputState.toast = toast
                self.isSyncing = false
                self.hostingController?.rootView = self.makeKeyboardView()
                self.scheduleToastDismissal(delay: toast == .failed ? 4.0 : 2.5)
            }
        }
    }

    /// `.completed / .failed` 停留片刻后自动收起；`started` 由同步结束直接替换。
    private func scheduleToastDismissal(delay: TimeInterval) {
        toastDismissTask?.cancel()
        let state = inputState
        let task = Task { [weak state] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { state?.toast = nil }
        }
        toastDismissTask = task
    }

    /// 提交当前拼音组合：优先空格确认，否则直接上屏 preedit 原文。
    private func commitPendingComposition() {
        guard !rimeContext.preedit.isEmpty else { return }
        if rimeContext.processKey(XK_space) {
            syncText()
        } else {
            commitRawPreedit(rimeContext.preedit)
        }
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

    /// 日志页「清空」：删除 keyboard.log（含轮转件）与崩溃标记。
    private func clearKeyboardLogs() {
        rimeContext.clearKeyboardLogs()
        rimeContext.keyboardLog("日志已清空")
    }

    /// 崩溃兜底记录：NSSetUncaughtExceptionHandler 处理 ObjC/Swift 未捕获异常，
    /// SIGSEGV/SIGBUS/SIGILL/SIGABRT 仅能尽力写一行（信号上下文里大多数调用
    /// 都不安全；这里只做一次小文件写，接受不可靠换可见性）。真正的崩溃
    /// 确认仍靠启动/deinit 标记对。
    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let rime = RimeContext.shared
            rime.keyboardLog("未捕获异常: \(exception.name.rawValue) - \(exception.reason ?? "")")
        }
        let signals: [Int32] = [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP]
        for sig in signals {
            signal(sig) { _ in
                // async-signal-unsafe 但只有一次小写：闪退现场比规范重要。
                if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let log = url.appendingPathComponent("Logs/keyboard.log")
                    let line = "[signal] 致命信号 \(sig)，进程即将终止\n"
                    if let data = line.data(using: .utf8),
                       let handle = try? FileHandle(forWritingTo: log) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    } else if let data = line.data(using: .utf8) {
                        try? FileManager.default.createDirectory(
                            at: log.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try? data.write(to: log)
                    }
                }
            }
        }
    }

    /// 本键盘上屏了非空文本，标记输入框已有文本（回车键高亮）。
    private func insertToProxy(_ text: String) {
        textDocumentProxy.insertText(text)
        inputState.hasInputText = true
    }

    /// 上屏最终文本。组合期 marked 区是原始拼音，直接 `unmarkText()` 会把拼音
    /// 固化进文档再拼上候选；改为以最终文本覆盖 marked 区后固化。
    private func commitReplacingMarkedText(_ text: String) {
        if displayedPreedit.isEmpty {
            insertToProxy(text)
        } else {
            let end = text.utf16.count
            textDocumentProxy.setMarkedText(text, selectedRange: NSRange(location: end, length: 0))
            textDocumentProxy.unmarkText()
            inputState.hasInputText = true
        }
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
