import Foundation
import Testing
@testable import KeyboardUI

struct KeyboardDiagnosticsTests {
    @Test("UTF-8 日志从多字节字符中间截取仍保留完整后续行")
    func unicodeTail() throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "中文中文中文\n完整第二行\n第三行\n".write(to: url, atomically: true, encoding: .utf8)
        let text = KeyboardDiagnostics.readTail(url, maxBytes: 35)
        #expect(text.contains("完整第二行"))
        #expect(text.contains("第三行"))
        #expect(!text.contains("�"))
    }

    @Test("清空日志保留运行标记，旧控制器退出不删除新会话标记")
    func sessionOwnership() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = KeyboardDiagnostics(directory: directory)
        log.beginSession("first")
        log.record("before clear")
        try log.clear()
        let marker = directory.appendingPathComponent("session.json")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!log.tail().contains("before clear"))
        log.beginSession("second")
        log.endSession("first")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        log.endSession("second")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("日志达到上限轮转且保留最近事件")
    func rotation() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = KeyboardDiagnostics(directory: directory)
        log.record(String(repeating: "a", count: 1 << 20))
        log.record("latest")
        #expect(log.tail().contains("latest"))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("keyboard.log.old").path))
    }
}
