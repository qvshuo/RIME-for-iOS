import Foundation

extension RimeContext {
    // MARK: - Logging

    /// 生命周期 / 错误级日志。打到 stderr（被 `redirectStderrToLogFile()` 统一
    /// 捕获进 quill.log）。不在按键热路径上调用。
    public func log(_ message: String) {
        let ts = Date().formatted(date: .omitted, time: .shortened)
        let line = "[\(ts)] \(message)"
        line.withCString { str in
            fputs(str, stderr)
            fputs("\n", stderr)
        }
    }

    public func exportLogURL() -> URL? {
        Paths.logDirectory?.appendingPathComponent(logFileName)
    }

    /// 启动时重定向 stderr，并保留一次轮转，供键盘日志页导出引擎诊断。
    private static let maxLogFileSize: UInt64 = 1 << 20 // 1 MiB

    public func redirectStderrToLogFile() {
        guard let url = Paths.logDirectory?.appendingPathComponent(logFileName) else { return }
        // 先回收 librime glog 每次进程遗留的文件：它们不自动清理，会无限累积。
        // 只删除 glog 级别文件，避免删除其他诊断目录。
        pruneGlogFiles()
        rotateLogFileIfNeeded(url)
        // withCString 保证 C 路径指针在 fopen 调用期间存活（`(NSString).utf8String`
        // 的指针只保证存活到当前表达式结束，跨语句使用是悬垂模式）。
        guard let file = url.path.withCString({ fopen($0, "a") }) else { return }
        dup2(fileno(file), STDERR_FILENO)
        fclose(file)
    }

    /// glog 的独立级别文件不会自行回收；诊断详情已包含在 stderr 中。
    private func pruneGlogFiles() {
        guard let dir = Paths.logDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in files {
            let name = url.lastPathComponent
            guard [".INFO", ".WARNING", ".ERROR", ".FATAL"].contains(where: name.contains) else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// 截断当前 inode，保留 stderr 的已打开文件描述符，后续引擎日志继续落到同一文件。
    public func clearLog() throws {
        guard let url = exportLogURL() else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
        }
        let old = url.appendingPathExtension("old")
        if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
    }

    private func rotateLogFileIfNeeded(_ url: URL) {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes?[.size] as? NSNumber, size.uint64Value >= Self.maxLogFileSize else { return }
        let oldPath = path + ".old"
        try? FileManager.default.removeItem(atPath: oldPath)
        try? FileManager.default.moveItem(atPath: path, toPath: oldPath)
    }
}
