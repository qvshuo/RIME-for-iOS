import Foundation

public enum SyncToast: Sendable, Equatable {
    case started
    case completed
    case failed

    public var message: String {
        switch self {
        case .started: return "正在同步…"
        case .completed: return "同步完成"
        case .failed: return "同步失败，请检查设置"
        }
    }
}
