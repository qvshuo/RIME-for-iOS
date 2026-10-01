import Foundation
import RimeEngine
import Synchronization

public enum WebDAVSync {
    private static let inFlight = Mutex(false)
    private static let engineQueue = DispatchQueue(label: "art.anjing.rimeios.librime.sync")

    /// 维护不可中断；会话清理排入同一队列，避免主线程等待维护锁。
    public static func runAfterSync(_ block: @escaping @Sendable () -> Void) {
        engineQueue.async(execute: block)
    }

    @discardableResult
    public static func sync() async -> Bool {
        let acquired = inFlight.withLock { running in
            guard !running else { return false }
            running = true
            return true
        }
        guard acquired else { return false }
        defer { inFlight.withLock { $0 = false } }
        let context = RimeContext.shared
        do {
            guard let saved = try WebDAVCredentialStore.shared.load(), let user = RimePaths.userDataDirectory else {
                context.log("WebDAVSync: missing credentials or user directory")
                return false
            }
            let credentials = try saved.validated()
            let ownID = credentials.installationID ?? "iPhone"
            let operation = WebDAVSyncOperation(
                client: WebDAVClient(credentials: credentials), root: credentials.syncPath ?? "Rime_Sync",
                installationID: ownID,
                staging: URL.temporaryDirectory.appendingPathComponent("RimeSync-\(UUID().uuidString)"),
                userDirectory: user,
                runEngine: { staging in try await runEngine(context: context, staging: staging, installationID: ownID) },
                log: { context.log("WebDAVSync: " + $0) }
            )
            context.log("WebDAVSync: begin")
            try await operation.run()
            context.log("WebDAVSync: completed")
            return true
        } catch {
            context.log("WebDAVSync: failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func runEngine(context: RimeContext, staging: URL, installationID: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            engineQueue.async {
                RimeContext.installationID = installationID
                let result = Result {
                    try context.setStagingDirectory(staging)
                    let syncResult = Result { try context.syncUserData() }
                    try context.clearStagingDirectory()
                    return try syncResult.get()
                }
                context.recreateSession()
                // resume 后等待者可立即继续，因此先完成重建再恢复 UI。
                continuation.resume(with: result)
            }
        }
    }

    /// 超时取消网络，但等待不可中断的维护退出后才恢复输入。
    @discardableResult
    public static func syncWithTimeout(_ timeout: Duration = .seconds(60)) async -> Bool {
        await race(operation: { await sync() }, deadline: { try? await Task.sleep(for: timeout) })
    }

    static func race(operation: @escaping @Sendable () async -> Bool,
                     deadline: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask(operation: operation)
            group.addTask { await deadline(); return false }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
