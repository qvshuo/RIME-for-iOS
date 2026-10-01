import Foundation

extension RimeContext {
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

    private func pruneGlogFiles() {
        guard let dir = RimePaths.logDirectory else { return }
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
