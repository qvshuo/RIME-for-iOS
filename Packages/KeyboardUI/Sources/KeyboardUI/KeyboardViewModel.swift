import SwiftUI
import Observation
import UIKit
import Models
import RimeEngine

public enum ShiftState: Equatable {
    case lowercase
    case uppercaseOnce
    case uppercaseLocked
}

public enum InputLanguage: Equatable {
    case chinese
    case english
}

/// `currentRows` 缓存键：行的可见内容只依赖布局 + 语言 + 大小写。
private struct CachedRowsKey: Equatable {
    let layout: KeyboardLayout
    let language: InputLanguage
    let shift: ShiftState
}

@MainActor
@Observable
public final class KeyboardViewModel {
    public var currentLayout: KeyboardLayout = .qwerty
    public var shiftState: ShiftState = .lowercase
    public var inputLanguage: InputLanguage = .chinese
    /// 布局加载失败时记录（键盘面板兜底展示），避免「空白键盘无提示」。
    public var errorMessage: String?

    private var cachedLayouts: [KeyboardLayout: [InputLanguage: LayoutDescriptor]] = [:]
    /// `currentRows` 缓存：敲键（仅 preedit/候选变化）不会使缓存失效、重建键描述。
    private var cachedRows: [RowDescriptor] = []
    private var cachedRowsKey: CachedRowsKey?
    private var startsLiteralComposition = false
    private var lastShiftTap = Date.distantPast
    private static let doubleTapInterval: TimeInterval = 0.35

    /// 时间源（测试可注入，使双击判定的时序可确定）。
    var now: () -> Date = Date.init

    /// 宿主请求的键盘类型与回车键类型（由键盘控制器写入）。
    public var keyboardType: UIKeyboardType = .default
    public var returnKeyType: UIReturnKeyType = .default

    /// 当前是否有未提交的拼音组合。
    public func needsConfirm(rimeContext: RimeContext?) -> Bool {
        guard let rimeContext else { return false }
        return !rimeContext.preedit.isEmpty
    }

    /// 实际显示的回车键文案；仅由行视图在自身 body 读取（不进键盘根 body）。
    public nonisolated static func effectiveReturnLabel(hasPreedit: Bool, hostLabel: String) -> String {
        hasPreedit ? "⏎" : hostLabel
    }

    /// 点击这些符号后直接回到字母键盘（数字/符号页通用）。
    private static let autoReturnSymbols: Set<String> = [
        "（", "）", "@", "“", "”", "。", "，", "、", "？", "！",
        "【", "】", "｛", "｝", "#", "%", "^", "*", "+", "=",
        "_", "\\", "|", "｜", "《", "》", "&", "·"
    ]

    public init() {
        loadLayouts()
    }

    public func loadLayouts() {
        for layout in KeyboardLayout.allCases {
            var perLanguage: [InputLanguage: LayoutDescriptor] = [:]
            for language in [InputLanguage.chinese, .english] {
                do {
                    perLanguage[language] = try LayoutParser.load(layoutFileName(for: layout, language: language))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            cachedLayouts[layout] = perLanguage
        }
    }

    public var currentRows: [RowDescriptor] {
        let key = CachedRowsKey(layout: currentLayout, language: inputLanguage, shift: shiftState)
        if let cachedRowsKey, cachedRowsKey == key {
            return cachedRows
        }
        guard let descriptor = cachedLayouts[currentLayout]?[inputLanguage] else { return [] }
        let rows = descriptor.rows.map { row in
            RowDescriptor(
                keys: row.keys.map(localizedDescriptor),
                leadingPadding: row.leadingPadding
            )
        }
        cachedRows = rows
        cachedRowsKey = key
        return rows
    }

    /// 数字/符号页按语言区分布局文件；字母页中英共用同一套。
    private func layoutFileName(for layout: KeyboardLayout, language: InputLanguage) -> String {
        switch layout {
        case .qwerty:
            return "qwerty"
        case .numbers:
            return language == .chinese ? "numbers-zh" : "numbers-en"
        case .symbols:
            return language == .chinese ? "symbols-zh" : "symbols-en"
        }
    }

    /// 布局/语言/大写相关的键动作：更新本机状态后映射为最终动作。
    /// 返回 nil 表示已被本层消费；非 nil 为应继续转发的动作。
    public func consume(_ action: KeyAction, rimeContext: RimeContext? = nil) -> KeyAction? {
        switch action {
        case .numbers:
            currentLayout = .numbers
            // 切到数字/符号键盘时消耗一次性大写状态。
            if shiftState == .uppercaseOnce {
                shiftState = .lowercase
            }
            return nil
        case .symbols:
            currentLayout = .symbols
            if shiftState == .uppercaseOnce {
                shiftState = .lowercase
            }
            return nil
        case .letters:
            currentLayout = .qwerty
            return nil
        case .shift:
            handleShiftTap()
            startsLiteralComposition = shiftState != .lowercase
            return nil
        case .toggleLanguage:
            startsLiteralComposition = false
            inputLanguage = inputLanguage == .chinese ? .english : .chinese
            // 切到英文时默认「首字母大写」一次，切回中文时回到小写。
            shiftState = (inputLanguage == .english) ? .uppercaseOnce : .lowercase
            return .toggleLanguage
        case .space:
            if usesLiteralComposition(in: rimeContext) {
                startsLiteralComposition = false
                return .composingInput(" ")
            }
            // 有未提交拼音时，空格统一按 RIME 上屏候选（在数字/符号页点「确认」也生效）。
            if needsConfirm(rimeContext: rimeContext) {
                return .space
            }
            // 中文（含数字/符号页）的空格交 RIME 处理：无组合时上屏空格、双击转「。」；
            // 英文/其他页直接上屏字面空格（双击在控制器转「.」）。
            if inputLanguage == .chinese {
                return .space
            }
            return .directInput(" ")
        case .character(let char):
            let result = shiftedCharacter(char)
            let composing = usesLiteralComposition(in: rimeContext)
            startsLiteralComposition = false
            // 一次性大写在任何字符键上都会消耗（含数字/符号页）：符号页「句末符号
            // 自动回字母页」场景下，若保留大写状态会导致回到字母页后下一个字母意外大写。
            if shiftState == .uppercaseOnce {
                shiftState = .lowercase
            }
            let transformed: KeyAction = composing ? .composingInput(result)
                : currentLayout == .qwerty ? .character(result) : .directInput(result)
            if currentLayout != .qwerty, Self.autoReturnSymbols.contains(result) {
                currentLayout = .qwerty
            }
            return transformed
        default:
            return action
        }
    }

    private func usesLiteralComposition(in engine: RimeContext?) -> Bool {
        guard let engine else { return false }
        // 手动 Shift 启动组合；英文模式默认的一次大写仍按普通英文输入处理。
        return startsLiteralComposition || shiftState == .uppercaseLocked || engine.isLiteralComposition
    }

    /// 宿主键盘类型变化：仅 `.asciiCapable` 强制英文，其余保持中文。
    public func handleKeyboardTypeChange(_ type: UIKeyboardType) {
        guard type != keyboardType else { return }
        startsLiteralComposition = false
        keyboardType = type
        inputLanguage = (type == .asciiCapable) ? .english : .chinese
        shiftState = (type == .asciiCapable) ? .uppercaseOnce : .lowercase
        // 字段切换回到字母页（不会进入数字/符号页）。
        if currentLayout != .qwerty {
            currentLayout = .qwerty
        }
    }

    /// 回车键类型变化：刷新动态标签。
    public func handleReturnKeyType(_ type: UIReturnKeyType) {
        guard type != returnKeyType else { return }
        returnKeyType = type
    }

    /// 回车键动态文本，映射到原生简体拼音键盘的按钮文案。
    public var returnKeyLabel: String {
        switch returnKeyType {
        case .go: return "前往"
        case .join: return "加入"
        case .next: return "下一步"
        case .route: return "路线"
        case .search, .google, .yahoo: return "搜索"
        case .send: return "发送"
        case .done: return "完成"
        case .emergencyCall: return "紧急呼叫"
        case .continue: return "继续"
        default: return "换行"
        }
    }

    /// 按当前语言改写切换键显示 label（动作本身不变）。回车键的动态 label/高亮
    /// 由行视图覆盖，不在此处理——否则每次敲键都会使 `currentRows` 缓存失效。
    private func localizedDescriptor(_ key: KeyDescriptor) -> KeyDescriptor {
        switch key.action {
        case .toggleLanguage:
            return key.with(label: inputLanguage == .chinese ? "中" : "英")
        case .letters:
            return key.with(label: inputLanguage == .chinese ? "拼音" : "ABC")
        case .character(let character):
            return key.with(label: shiftedCharacter(character))
        default:
            return key
        }
    }

    /// 字母键显示与输入统一按 shift 状态决定是否大写。
    private func shiftedCharacter(_ character: String) -> String {
        guard currentLayout == .qwerty,
              character.count == 1,
              shiftState != .lowercase else { return character }
        return character.uppercased()
    }

    /// 单击：进入一次大写（输入一个字母后自动恢复），或取消当前大写锁定；
    /// 双击（0.35s 内两次按下）：锁定大写，直到再次单击取消。
    private func handleShiftTap() {
        let now = self.now()
        let isDoubleTap = now.timeIntervalSince(lastShiftTap) < Self.doubleTapInterval
        lastShiftTap = now
        if isDoubleTap, shiftState != .uppercaseLocked {
            shiftState = .uppercaseLocked
            return
        }
        switch shiftState {
        case .lowercase:
            shiftState = .uppercaseOnce
        case .uppercaseOnce, .uppercaseLocked:
            shiftState = .lowercase
        }
    }
}

