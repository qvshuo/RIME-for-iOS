import Foundation
import Testing
@testable import RimeEngine

struct BoundedLogFileTests {
    @Test("持续输出和单次超大输出都受大小上限约束")
    func boundedOutput() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = BoundedLogFile(url: root.appendingPathComponent("engine.log"), limit: 1024)
        for _ in 0..<100 { try file.append(Data(repeating: 65, count: 256)) }
        try file.append(Data(repeating: 66, count: 4096))
        for url in [file.url, file.url.appendingPathExtension("old")] {
            #expect(try Data(contentsOf: url).count <= 1024)
        }

    }

    @Test("并发写入和轮转串行化，保留完整事件")
    func concurrentWrites() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = BoundedLogFile(url: root.appendingPathComponent("engine.log"), limit: 1024)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    try file.append(Data("event \(index)\n".utf8))
                }
            }
            try await group.waitForAll()
        }
        try file.append(Data("latest\n".utf8))
        #expect(try String(contentsOf: file.url, encoding: .utf8).contains("latest"))
    }
}
