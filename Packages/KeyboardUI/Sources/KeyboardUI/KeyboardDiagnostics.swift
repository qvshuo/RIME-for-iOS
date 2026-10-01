import Foundation
import Darwin
import RimeEngine
import Synchronization

public final class KeyboardDiagnostics: Sendable {
    public static let shared = KeyboardDiagnostics(directory:
        (Paths.logDirectory ?? URL.temporaryDirectory).appendingPathComponent("Keyboard", isDirectory: true)
    )

    let directory: URL
    private let lock = Mutex(())
    private var logURL: URL { directory.appendingPathComponent("keyboard.log") }
    private var markerURL: URL { directory.appendingPathComponent("session.json") }
    private let limit = 256 * 1024

    private struct Session: Codable {
        let pid: Int32
        let id: String
    }

    init(directory: URL) { self.directory = directory }

    public func record(_ message: String) {
        lock.withLock { _ in append(message) }
    }

    public func beginSession(_ id: String) {
        lock.withLock { _ in
            prepareDirectory()
            if let data = try? Data(contentsOf: markerURL),
               let previous = try? JSONDecoder().decode(Session.self, from: data),
               previous.pid != getpid(), kill(previous.pid, 0) == -1, errno == ESRCH {
                // iOS 可直接回收扩展；标记只能确认未完成清理，不能证明崩溃。
                append("上次运行未完成清理，可能由系统回收；崩溃原因请查看系统诊断。")
            }
            if let data = try? JSONEncoder().encode(Session(pid: getpid(), id: id)) {
                try? data.write(to: markerURL, options: .atomic)
            }
            append("键盘启动")
        }
    }

    public func endSession(_ id: String) {
        lock.withLock { _ in
            guard let data = try? Data(contentsOf: markerURL),
                  let current = try? JSONDecoder().decode(Session.self, from: data), current.id == id else { return }
            append("键盘控制器释放")
            try? FileManager.default.removeItem(at: markerURL)
        }
    }

    func tail() -> String {
        lock.withLock { _ in
            var sections = ["键盘\n" + Self.readTail(logURL, maxBytes: 8192)]
            if let engine = RimeContext.shared.exportLogURL() {
                sections.append("引擎\n" + Self.readTail(engine, maxBytes: 8192))
            }
            return sections.joined(separator: "\n\n")
        }
    }

    /// 生成独立快照，分享期间继续写日志或清空日志不会改变导出文件。
    func export() throws -> URL {
        try lock.withLock { _ in
            let sources = [logURL.appendingPathExtension("old"), logURL,
                           RimeContext.shared.exportLogURL()?.appendingPathExtension("old"),
                           RimeContext.shared.exportLogURL()].compactMap { $0 }
            let text = sources.map { url in
                "--- \(url.lastPathComponent) ---\n" + Self.readTail(url, maxBytes: limit)
            }.joined(separator: "\n\n")
            let folder = directory.appendingPathComponent("Export", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Quill-diagnostics.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    func clear() throws {
        try lock.withLock { _ in
            prepareDirectory()
            try Data().write(to: logURL)
            let old = logURL.appendingPathExtension("old")
            if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
            // 运行标记不属于日志，清空不能让本次运行失去退出检测。
            append("日志已清空")
        }
    }

    static func readTail(_ url: URL, maxBytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try handle.seek(toOffset: offset)
            var data = try handle.read(upToCount: maxBytes) ?? Data()
            // 先按字节丢弃残行，避免 UTF-8 多字节字符被截断导致整段读取失败。
            if offset > 0, let newline = data.firstIndex(of: 10) { data = data.suffix(from: data.index(after: newline)) }
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }

    private func prepareDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func append(_ message: String) {
        prepareDirectory()
        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        let data = Data("[\(Date().ISO8601Format())] \(message)\n".utf8).suffix(limit)
        if let size = attributes?[.size] as? NSNumber, size.intValue + data.count > limit {
            let old = logURL.appendingPathExtension("old")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: logURL, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch { }
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
