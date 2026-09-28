import Foundation
import RimeEngine
import Synchronization

/// WebDAV 同步编排（Squirrel 逻辑）：清空暂存目录 → 下载各设备目录的相关文件 →
/// 把 installation.yaml 的 sync_dir 指到暂存目录 → `RimeSyncUserData` 导出+合并 →
/// 上传本机导出目录。
///
/// 只同步用户词库与自定义短语两个文件；暂存目录用完即弃，不留本地缓存。
/// 成功与否仅以返回值表达（超时也按失败处理）；失败原因经 `RimeContext.log()` 记录。
public enum WebDAVSync {
    /// 远程同步根目录（相对 baseURL）。默认 `Rime_Sync`，可在键盘同步页自定义。
    public static var syncRootPath: String {
        let saved = WebDAVCredentialStore.load()?.syncPath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "Rime_Sync" : saved
    }

    /// 同步暂存目录：每次同步前清空重建。
    static var stagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RimeSyncStage", isDirectory: true)
    }

    /// librime 同步是阻塞调用，不能在 Swift 协作线程池上等待，放专用串行队列。
    private static let librimeSyncQueue = DispatchQueue(label: "art.anjing.quill.librime.sync")

    /// 在 librime 同步专用串行队列上执行引擎操作（如同步后的会话重建）。
    /// 与在途同步 FIFO 串行；僵尸同步持引擎锁时主线程直接调用会阻塞键盘。
    public static func runAfterSync(_ block: @escaping @Sendable () -> Void) {
        librimeSyncQueue.async(execute: block)
    }

    /// 在专用队列上执行 librime 同步导出 + 合并。
    private static func runLibrimeSync(context: RimeContext, staging: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            librimeSyncQueue.async {
                // 无论成功与否都复位目录覆盖，避免同步失败后残留暂存指向。
                context.setStagingDirectory(staging)
                defer { context.clearStagingDirectory() }
                do {
                    continuation.resume(returning: try context.syncUserData())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 只同步这两个文件：用户词库与自定义短语。
    private static func relevantFile(_ name: String) -> Bool {
        name == "luna_pinyin_extended.userdb.txt" || name == "custom_phrase.txt"
    }

    /// 单一在途标记：超时输家不会被取消，并发触发会交错读写同一暂存目录与词库。
    private static let inFlight = Mutex(false)

    /// 完整同步一次，返回是否成功。进度经 `RimeContext.log()` 记录。
    /// 与上一次同步在途时（含超时后仍在后台跑完的）直接返回 false，不重复执行。
    @discardableResult
    public static func sync() async -> Bool {
        let context = RimeContext.shared
        context.log("WebDAVSync: begin")
        if inFlight.withLock({ $0 }) {
            context.log("WebDAVSync: already in flight, skip")
            return false
        }
        inFlight.withLock { $0 = true }
        defer { inFlight.withLock { $0 = false } }
        guard let credentials = WebDAVCredentialStore.load() else {
            context.log("WebDAVSync: no credentials saved")
            return false
        }
        // 引擎层保持后端无关，安装 ID 由同步层按保存的凭据设置。
        RimeContext.installationID = credentials.installationID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Quill"

        let client = WebDAVClient(credentials: credentials)
        let rootPath = syncRootPath

        do {
            let staging = stagingDirectory
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            var devices: [String] = []
            do {
                let entries = try await client.listDirectory(relativePath: rootPath)
                devices = entries.filter(\.isDirectory).map(\.name)
                context.log("WebDAVSync: devices under Rime_Sync/ = \(devices)")
            } catch let error as WebDAVClient.WebDAVError {
                // 404 = 目录还不存在，跳过下载，直接导出+上传。
                if case .serverError(let code) = error, code == 404 {
                    context.log("WebDAVSync: Rime_Sync/ not found, will create")
                } else {
                    throw error
                }
            }

            for device in devices where device != RimeContext.installationID {
                // 本机目录跳过下载：librime 合并的是外来数据，本机导出由
                // `syncUserData` 自己生成，先下载纯属浪费（慢挂载上一次 4.5s+）。
                let remoteDir = "\(rootPath)/\(device)"
                let files: [String]
                do {
                    let entries = try await client.listDirectory(relativePath: remoteDir)
                    files = entries.filter { !$0.isDirectory && relevantFile($0.name) }.map(\.name)
                } catch {
                    context.log("WebDAVSync: list \(device) failed: \(error.localizedDescription)")
                    continue
                }
                context.log("WebDAVSync: download \(device): \(files)")
                for file in files {
                    do {
                        let data = try await client.download(relativePath: "\(remoteDir)/\(file)")
                        let localDir = staging.appendingPathComponent(device, isDirectory: true)
                        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                        try data.write(to: localDir.appendingPathComponent(file), options: .atomic)
                        context.log("WebDAVSync: downloaded \(device)/\(file) (\(data.count) bytes)")
                    } catch {
                        context.log("WebDAVSync: download \(device)/\(file) failed: \(error.localizedDescription)")
                    }
                }
            }

            // 把其他设备的 custom_phrase.txt 覆盖进本地用户目录：
            // librime 只合并 *.userdb.txt，.txt 需手动应用、下次会话生效。
            if let userDir = Paths.userDataDirectory {
                try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
                for device in devices where device != RimeContext.installationID {
                    let deviceDir = staging.appendingPathComponent(device, isDirectory: true)
                    let source = deviceDir.appendingPathComponent("custom_phrase.txt")
                    if FileManager.default.fileExists(atPath: source.path) {
                        let target = userDir.appendingPathComponent("custom_phrase.txt")
                        try? FileManager.default.removeItem(at: target)
                        try? FileManager.default.copyItem(at: source, to: target)
                        context.log("WebDAVSync: applied custom_phrase.txt from \(device)")
                    }
                }
            }

            // 指向暂存目录并跑 librime 同步（导出 + 合并）。
            let result = try await Self.runLibrimeSync(context: context, staging: staging)
            context.log("WebDAVSync: librime sync done, export dir = \(result.path)")

            // 上传本机导出目录回 WebDAV。单个文件读写失败不中断整体同步，
            // 仅记录日志（跳过该文件）。
            let ownID = RimeContext.installationID
            let ownDir = staging.appendingPathComponent(ownID, isDirectory: true)
            // 首次同步时同步根目录可能尚未创建，先 MKCOL 根目录再建本机目录
            // （父目录缺失时 MKCOL 子目录会返回 409；MKCOL 已存在目录返回 405，视为成功）。
            try await client.createDirectory(relativePath: rootPath)
            try await client.createDirectory(relativePath: "\(rootPath)/\(ownID)")
            if let files = try? FileManager.default.contentsOfDirectory(
                at: ownDir, includingPropertiesForKeys: nil
            ) {
                for file in files where relevantFile(file.lastPathComponent) {
                    guard let data = try? Data(contentsOf: file) else {
                        context.log("WebDAVSync: read \(ownID)/\(file.lastPathComponent) failed, skip")
                        continue
                    }
                    do {
                        let remote = "\(rootPath)/\(ownID)/\(file.lastPathComponent)"
                        try await client.upload(relativePath: remote, data: data)
                        context.log("WebDAVSync: uploaded \(ownID)/\(file.lastPathComponent) (\(data.count) bytes)")
                    } catch {
                        context.log("WebDAVSync: upload \(ownID)/\(file.lastPathComponent) failed: \(error.localizedDescription)")
                    }
                }
            }
            context.log("WebDAVSync: completed")
            return true
        } catch {
            context.log("WebDAVSync: failed: \(error.localizedDescription)")
            return false
        }
    }

    /// 带超时的同步，超时按失败处理。用「竞速」而非「取消」：中途取消会让
    /// `withCheckedThrowingContinuation` 与队列回调双 resume；输家在后台跑完即被丢弃。
    @discardableResult
    public static func syncWithTimeout(_ timeout: Duration = .seconds(60)) async -> Bool {
        await withCheckedContinuation { continuation in
            let winner = RaceWinner()
            let syncTask = Task {
                let result = await sync()
                winner.finish(result: result, continuation)
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                winner.finish(result: false, continuation)
            }
            // 两个 Task 被子闭包强持有即可保持存活；输家跑完即被丢弃。
            _ = syncTask
            _ = timeoutTask
        }
    }

    /// 竞速辅助：两个子任务谁先调用 `finish` 就 resume 一次，后到者忽略
    /// （`CheckedContinuation` 只能 resume 一次）。
    private final class RaceWinner: Sendable {
        private let winner = Mutex(false)

        func finish(result: Bool, _ continuation: CheckedContinuation<Bool, Never>) {
            let shouldResume = winner.withLock { state in
                if state { return false }
                state = true
                return true
            }
            if shouldResume {
                continuation.resume(returning: result)
            }
        }
    }
}
