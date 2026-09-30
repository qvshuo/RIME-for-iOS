import Foundation
import Synchronization

extension RimeContext {
    // MARK: - Sync (安装信息 / 用户词典同步)

    /// 本设备的安装 ID，即 `sync/<installation_id>/` 子目录名。引擎层后端无关，
    /// 由同步层按保存的凭据设置。多处读写，用锁保护。
    private static let installationIDStorage = Mutex<String>("Quill")
    public static var installationID: String {
        get { installationIDStorage.withLock { $0 } }
        set { installationIDStorage.withLock { $0 = newValue } }
    }

    /// librime 同步目录（`user_data_dir/sync`，或 installation.yaml 里配置的 sync_dir）。
    /// 同步期间 installation.yaml 的 sync_dir 会被改写为暂存目录，本目录仅作启动时默认值。
    // MARK: - Sync (暂存目录覆盖)

    /// 同步期间的暂存目录覆盖；结束后清空。多处读写，用锁保护。
    private static let stagingDirectoryOverrideStorage = Mutex<URL?>(nil)
    private static var stagingDirectoryOverride: URL? {
        get { stagingDirectoryOverrideStorage.withLock { $0 } }
        set { stagingDirectoryOverrideStorage.withLock { $0 = newValue } }
    }

    /// 让 installation.yaml 的 `sync_dir` 指向同步暂存目录，并记录导出目录。
    /// 同步完成后调用 `clearStagingDirectory()` 复位。
    public func setStagingDirectory(_ stagingDir: URL) {
        Self.stagingDirectoryOverride = stagingDir
        try? FileManager.default.createDirectory(
            at: stagingDir, withIntermediateDirectories: true
        )
        rewriteInstallationInfo(syncDir: stagingDir)
    }

    public func clearStagingDirectory() {
        Self.stagingDirectoryOverride = nil
    }

    /// 确保 installation.yaml 的 installation_id / backup_config_files / sync_dir 就绪。
    func ensureInstallationInfo() {
        guard let dir = Paths.userDataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let root = Self.stagingDirectoryOverride ?? Paths.syncDirectory ?? dir
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )

        rewriteInstallationInfo(syncDir: root)
    }

    /// 写入 installation.yaml：`installation_id` + `backup_config_files` + `sync_dir`。
    /// 读改写全程持锁：`ensureInstallationInfo`（启动任务）与 `setStagingDirectory`
    /// （同步队列）可能交错，无锁会丢更新（如暂存覆盖被启动默认值冲掉）。
    private static let installationFileLock = Mutex<Void>(())

    private func rewriteInstallationInfo(syncDir: URL) {
        guard let dir = Paths.userDataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: syncDir, withIntermediateDirectories: true
        )

        Self.installationFileLock.withLock { _ in
            let file = dir.appendingPathComponent("installation.yaml")
            // 按行拆分时剥掉 CRLF 的 \r 残留，避免写回的 YAML 行尾混入 \r。
            var lines = ((try? String(contentsOf: file, encoding: .utf8))?
                .components(separatedBy: "\n") ?? [])
                .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("installation_id:") }
            lines.insert("installation_id: \(yamlString(Self.installationID))", at: 0)
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("backup_config_files:") }
            lines.append("backup_config_files: true")
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("sync_dir:") }
            lines.append("sync_dir: \(yamlString(syncDir.path))")
            do {
                try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            } catch {
                // 写失败若被吞掉，librime 会按旧 sync_dir 导出/合并，同步静默错位——必须留痕。
                log("installation.yaml write failed: \(error.localizedDescription)")
            }
        }
        log("sync_dir = \(syncDir.path)")
    }

    // JSON 字符串也是合法 YAML 标量，避免安装 ID 和目录中的引号破坏配置。
    private func yamlString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// 跑一次 librime 同步：把本机用户词典导出到同步暂存目录的
    /// `<installation_id>/` 下，并合并暂存目录里其他设备的 `*.userdb.txt`。
    /// 必须先 `setStagingDirectory(_:)` 设置暂存目录，否则抛 `missingDirectory`。
    /// `RimeSyncUserData` 异步执行，须 `join_maintenance_thread` 等待完成。
    /// 持锁执行：librime 非线程安全，若与输入热路径（processKey）并发会崩。
    @discardableResult
    public func syncUserData() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard let staging = Self.stagingDirectoryOverride else {
            throw RimeError.missingDirectory
        }
        let exportDir = staging.appendingPathComponent(Self.installationID, isDirectory: true)
        guard let sync = rimeAPI.sync_user_data else {
            throw RimeError.syncFailed
        }
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        guard sync() else {
            throw RimeError.syncFailed
        }
        rimeAPI.join_maintenance_thread!()
        return exportDir
    }
}