import Foundation
import Synchronization

extension RimeContext {
    private static let installationIDStorage = Mutex<String>("iPhone")
    public static var installationID: String {
        get { installationIDStorage.withLock { $0 } }
        set { installationIDStorage.withLock { $0 = newValue } }
    }

    private static let stagingDirectoryOverrideStorage = Mutex<URL?>(nil)
    private static var stagingDirectoryOverride: URL? {
        get { stagingDirectoryOverrideStorage.withLock { $0 } }
        set { stagingDirectoryOverrideStorage.withLock { $0 = newValue } }
    }

    public func setStagingDirectory(_ stagingDir: URL) throws {
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try Self.installationFileLock.withLock {
            try rewriteInstallationInfo(syncDir: stagingDir)
            Self.stagingDirectoryOverride = stagingDir
        }
    }

    public func clearStagingDirectory() throws {
        try Self.installationFileLock.withLock {
            Self.stagingDirectoryOverride = nil
            try ensureInstallationInfo()
        }
    }

    func ensureInstallationInfo() throws {
        try Self.installationFileLock.withLock {
            guard let dir = RimePaths.userDataDirectory else { throw RimeError.missingDirectory }
            let root = Self.stagingDirectoryOverride ?? RimePaths.syncDirectory ?? dir
            try rewriteInstallationInfo(syncDir: root)
        }
    }

    /// 启动与同步可能交错，installation.yaml 的读改写须全程持锁。
    private static let installationFileLock = NSRecursiveLock()

    private func rewriteInstallationInfo(syncDir: URL) throws {
        guard let dir = RimePaths.userDataDirectory else { throw RimeError.missingDirectory }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)

        try Self.installationFileLock.withLock {
            let file = dir.appendingPathComponent("installation.yaml")
            // 按行拆分时剥掉 CRLF 的 \r 残留，避免写回的 YAML 行尾混入 \r。
            var lines = ((try? String(contentsOf: file, encoding: .utf8))?
                .components(separatedBy: "\n") ?? [])
                .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("installation_id:") }
            lines.insert("installation_id: \(try yamlString(Self.installationID))", at: 0)
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("backup_config_files:") }
            lines.append("backup_config_files: true")
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("sync_dir:") }
            lines.append("sync_dir: \(try yamlString(syncDir.path))")
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        log("sync_dir = \(syncDir.path)")
    }

    // JSON 字符串也是合法 YAML 标量，避免安装 ID 和目录中的引号破坏配置。
    private func yamlString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// 先设置暂存目录；须等待维护线程退出才能恢复输入或删除暂存文件。
    @discardableResult
    public func syncUserData() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { throw RimeError.syncFailed }
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
