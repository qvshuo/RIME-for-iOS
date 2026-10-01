import Foundation
import Darwin

final class EngineLogCapture: @unchecked Sendable {
    static let shared = EngineLogCapture()
    private let queue = DispatchQueue(label: "art.anjing.quill.engine-log", qos: .utility)
    private var source: DispatchSourceRead?
    private var file: BoundedLogFile?
    private var readDescriptor: Int32 = -1

    func start(at url: URL) {
        queue.sync {
            guard source == nil else { return }
            var descriptors: [Int32] = [0, 0]
            guard pipe(&descriptors) == 0 else { return }
            let reader = descriptors[0]
            let writer = descriptors[1]
            guard fcntl(reader, F_SETFL, O_NONBLOCK) != -1, dup2(writer, STDERR_FILENO) != -1 else {
                close(reader)
                close(writer)
                return
            }
            close(writer)
            readDescriptor = reader
            file = BoundedLogFile(url: url)
            let source = DispatchSource.makeReadSource(fileDescriptor: reader, queue: queue)
            source.setEventHandler { [weak self] in self?.drain() }
            source.setCancelHandler { close(reader) }
            self.source = source
            source.resume()
        }
    }

    private func drain() {
        guard readDescriptor >= 0, let file else { return }
        var buffer = [UInt8](repeating: 0, count: 8192)
        for _ in 0..<32 {
            let count = read(readDescriptor, &buffer, buffer.count)
            guard count > 0 else { return }
            // 写入失败不能再写 stderr，否则会递归放大日志。
            try? file.append(Data(buffer.prefix(count)))
        }
    }
}
