import Foundation
import Observation
import Models
import Sync

/// 进程级同步状态跨控制器重建保留，避免键盘重新出现时丢失维护门禁。
@MainActor
@Observable
public final class KeyboardSyncState {
    public static let shared = KeyboardSyncState()
    public private(set) var isSyncing = false
    public private(set) var toast: SyncToast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {}

    public func start() {
        guard !isSyncing else { return }
        isSyncing = true
        dismissTask?.cancel()
        toast = .started
        KeyboardDiagnostics.shared.record("手动同步开始")
        Task {
            let success = await WebDAVSync.syncWithTimeout()
            KeyboardDiagnostics.shared.record("手动同步结束 success=\(success)")
            isSyncing = false
            toast = success ? .completed : .failed
            dismissTask = Task {
                do { try await Task.sleep(for: .seconds(success ? 2.5 : 4)) } catch { return }
                toast = nil
            }
        }
    }
}
