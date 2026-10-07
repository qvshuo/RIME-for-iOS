import Foundation
import Observation
import UIKit
import KeyboardModels
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

private struct CachedRowsKey: Equatable {
    let layout: KeyboardLayout
    let language: InputLanguage
    let shift: ShiftState
}

@MainActor
@Observable
public final class KeyboardInputModel {
    public var currentLayout: KeyboardLayout = .qwerty
    public var shiftState: ShiftState = .lowercase
    public var inputLanguage: InputLanguage = .chinese
    public var errorMessage: String?

    @ObservationIgnored private var cachedLayouts: [KeyboardLayout: [InputLanguage: LayoutDescriptor]] = [:]
    @ObservationIgnored private var cachedRows: [RowDescriptor] = []
    @ObservationIgnored private var cachedRowsKey: CachedRowsKey?
    @ObservationIgnored private var startsLiteralComposition = false
    @ObservationIgnored private var lastShiftTap = Date.distantPast
    private static let doubleTapInterval: TimeInterval = 0.35

    @ObservationIgnored var now: () -> Date = Date.init

    public var keyboardType: UIKeyboardType = .default
    public var returnKeyType: UIReturnKeyType = .default

    public nonisolated static func effectiveReturnLabel(hasPreedit: Bool, hostLabel: String) -> String {
        hasPreedit ? "⏎" : hostLabel
    }

    private static let autoReturnSymbols: Set<String> = [
        "（", "）", "@", "“", "”", "。", "，", "、", "？", "！",
        "【", "】", "｛", "｝", "#", "%", "^", "*", "+", "=",
        "_", "\\", "|", "｜", "《", "》", "&", "·"
    ]

    public init() {
        loadLayouts()
    }

    private func loadLayouts() {
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

    /// 返回 nil 表示动作已消费；其余动作交给宿主输入控制器。
    public func consume(_ action: KeyAction, rimeContext: RimeContext? = nil) -> KeyAction? {
        switch action {
        case .numbers:
            currentLayout = .numbers
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
            shiftState = (inputLanguage == .english) ? .uppercaseOnce : .lowercase
            return .toggleLanguage
        case .space:
            if rimeContext?.preedit.isEmpty == false {
                return .space
            }
            if inputLanguage == .chinese {
                return .space
            }
            return .directInput(" ")
        case .character(let char):
            let result = shiftedCharacter(char)
            let composing = usesLiteralComposition(in: rimeContext)
            startsLiteralComposition = false
            // 符号后可能回到字母页；一次大写不能残留到下一字符。
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

    public func handleKeyboardTypeChange(_ type: UIKeyboardType) {
        guard type != keyboardType else { return }
        startsLiteralComposition = false
        keyboardType = type
        inputLanguage = (type == .asciiCapable) ? .english : .chinese
        shiftState = (type == .asciiCapable) ? .uppercaseOnce : .lowercase
        if currentLayout != .qwerty {
            currentLayout = .qwerty
        }
    }

    public func handleReturnKeyType(_ type: UIReturnKeyType) {
        guard type != returnKeyType else { return }
        returnKeyType = type
    }

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

    /// 回车标签由行视图覆盖，避免组合变化使静态布局缓存失效。
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

    private func shiftedCharacter(_ character: String) -> String {
        guard currentLayout == .qwerty,
              character.count == 1,
              shiftState != .lowercase else { return character }
        return character.uppercased()
    }

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
