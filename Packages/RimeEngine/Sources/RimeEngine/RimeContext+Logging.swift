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

    // MARK: - Keyboard log

    /// 键盘扩展专用日志（`keyboard.log`）：面板节点、崩溃报告、同步生命周期。
    /// 与引擎日志分离，查闪退不用在 glog/RIME 输出里翻找。
    public func keyboardLog(_ message: String) {
        let ts = Date().formatted(date: .numeric, time: .standard)
        let line = "[\(ts)] \(message)\n"
        guard let url = keyboardLogURL() else { return }
        rotateKeyboardLogIfNeeded(url)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func keyboardLogURL() -> URL? {
        Paths.logDirectory?.appendingPathComponent(keyboardLogFileName)
    }

    /// 清空键盘日志与崩溃标记（日志页「清空」按钮）。
    public func clearKeyboardLogs() {
        if let url = keyboardLogURL() {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + ".old")
        }
        if let marker = crashMarkerURL() {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    /// 键盘日志轮转阈值（与 quill.log 一致；追加式写，每次写入前检查）。
    private static let maxKeyboardLogSize: UInt64 = 1 << 20 // 1 MiB

    private func rotateKeyboardLogIfNeeded(_ url: URL) {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes?[.size] as? NSNumber,
              size.uint64Value >= Self.maxKeyboardLogSize else { return }
        let oldPath = path + ".old"
        try? FileManager.default.removeItem(atPath: oldPath)
        try? FileManager.default.moveItem(atPath: path, toPath: oldPath)
    }

    // MARK: - Crash detection

    /// 上次键盘运行未正常退出的崩溃标记（viewDidLoad 写入、deinit 清除）。
    private func crashMarkerURL() -> URL? {
        Paths.logDirectory?.appendingPathComponent("keyboard_crash.marker")
    }

    /// viewDidLoad 调用：写入运行标记；若上次的标记还在，说明上次未走到 deinit，
    /// 把崩溃事件记入键盘日志后覆盖标记。返回是否检测到上次崩溃。
    @discardableResult
    public func recordKeyboardLaunch() -> Bool {
        guard let marker = crashMarkerURL() else { return false }
        let crashed = FileManager.default.fileExists(atPath: marker.path)
        if crashed {
            keyboardLog("检测到上次键盘未正常退出（疑似闪退/Jetsam）")
        }
        try? Date().ISO8601Format().write(to: marker, atomically: true, encoding: .utf8)
        return crashed
    }

    /// deinit 调用：正常退出，清除崩溃标记。
    public func recordKeyboardExit() {
        guard let marker = crashMarkerURL() else { return }
        try? FileManager.default.removeItem(at: marker)
    }

    /// 把 stderr（NSLog / glog 输出）重定向到日志文件，这样 App 主页的日志
    /// 才能看到 RIME 引擎的真实日志。fcitx5-ios 同款做法。
    /// 每次启动检查文件大小，超过阈值时轮转一次（quill.log → quill.log.old），
    /// 防止 stderr 重定向让日志文件无限增长。
    private static let maxLogFileSize: UInt64 = 1 << 20 // 1 MiB

    public func redirectStderrToLogFile() {
        guard let url = Paths.logDirectory?.appendingPathComponent(logFileName) else { return }
        // 先回收 librime glog 每次进程遗留的文件：它们不自动清理，会无限累积。
        // 只保留 quill.log 与其 .old 轮转件；真正的 RIME/glog 详情仍走 stderr 进 quill.log。
        pruneGlogFiles()
        rotateLogFileIfNeeded(url)
        // withCString 保证 C 路径指针在 fopen 调用期间存活（`(NSString).utf8String`
        // 的指针只保证存活到当前表达式结束，跨语句使用是悬垂模式）。
        guard let file = url.path.withCString({ fopen($0, "a") }) else { return }
        dup2(fileno(file), STDERR_FILENO)
        fclose(file)
    }

    /// 删除 `Paths.logDirectory` 里非 `quill.log(.old)` 的残留文件（glog 按
    /// 进程名+级别+pid 生成 `*.INFO/WARNING/ERROR/FATAL`，含轮转后缀，长期累积）。
    private func pruneGlogFiles() {
        guard let dir = Paths.logDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        let keep = Set([logFileName, logFileName + ".old"])
        for url in files where !keep.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
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
