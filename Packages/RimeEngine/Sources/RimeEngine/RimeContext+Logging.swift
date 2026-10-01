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
        logURL
    }

    public func redirectStderrToLogFile() {
        guard let url = exportLogURL() else { return }
        pruneGlogFiles()
        EngineLogCapture.shared.start(at: url)
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

}
