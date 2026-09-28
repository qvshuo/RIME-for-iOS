import Foundation

/// 按键动作，键盘 UI 产生后交给控制器处理。
public enum KeyAction: Sendable, Equatable {
    case character(String)
    case directInput(String)
    case backspace
    case space
    case startSync
    case `return`
    case shift
    case numbers
    case letters
    case symbols
    case toggleLanguage
    case selectCandidate(Int)
    /// 清空日志文件（键盘日志页）。
    case clearLogs
}

public extension KeyAction {
    var isReturn: Bool {
        if case .return = self { return true }
        return false
    }

    var isSpace: Bool {
        if case .space = self { return true }
        return false
    }

    var isShift: Bool {
        if case .shift = self { return true }
        return false
    }

    var isBackspace: Bool {
        if case .backspace = self { return true }
        return false
    }

    var isToggle: Bool {
        switch self {
        case .numbers, .symbols: return true
        default: return false
        }
    }

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}
