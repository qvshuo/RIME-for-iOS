import Foundation

public final class BoundedLogFile: @unchecked Sendable {
    let url: URL
    public let limit: Int
    private let lock = NSLock()

    public init(url: URL, limit: Int = 256 * 1024) {
        precondition(limit > 0)
        self.url = url
        self.limit = limit
    }

    public func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let chunk = data.suffix(limit)
        // URL resource values 可缓存，轮转必须读取当前文件大小。
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size + chunk.count > limit {
            let old = url.appendingPathExtension("old")
            if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
            if size > limit {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(size - limit))
                try (handle.read(upToCount: limit) ?? Data()).write(to: old)
                try FileManager.default.removeItem(at: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: url, to: old)
            }
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try chunk.write(to: url)
        } else {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: chunk)
        }
    }

}
