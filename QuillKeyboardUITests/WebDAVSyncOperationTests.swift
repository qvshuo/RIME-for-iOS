import Foundation
import Testing
@testable import Sync

struct WebDAVSyncOperationTests {
    private actor Server: WebDAVTransport {
        let failDownload: Bool
        let failUpload: Bool
        var uploads: [String: Data] = [:]
        var directories: [String] = []
        init(failDownload: Bool = false, failUpload: Bool = false) {
            self.failDownload = failDownload
            self.failUpload = failUpload
        }
        func listDirectory(relativePath: String) async throws -> [WebDAVClient.Entry] {
            if relativePath == "nested/Rime_Sync" {
                return [.init(name: "foreign", isDirectory: true), .init(name: "own", isDirectory: true)]
            }
            return [.init(name: "custom_phrase.txt", isDirectory: false), .init(name: "private.txt", isDirectory: false)]
        }
        func download(relativePath: String) async throws -> Data {
            if failDownload { throw URLError(.cannotConnectToHost) }
            return Data("foreign phrases".utf8)
        }
        func upload(relativePath: String, data: Data) async throws {
            if failUpload { throw URLError(.cannotConnectToHost) }
            uploads[relativePath] = data
        }
        func createDirectory(relativePath: String) async throws { directories.append(relativePath) }
    }

    private func operation(server: Server, root: URL) -> WebDAVSyncOperation {
        WebDAVSyncOperation(client: server, root: "nested/Rime_Sync", installationID: "own",
                            staging: root.appendingPathComponent("staging"), userDirectory: root.appendingPathComponent("user"),
                            runEngine: { staging in
                                let directory = staging.appendingPathComponent("own")
                                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                try Data("dictionary".utf8).write(to: directory.appendingPathComponent("luna_pinyin_extended.userdb.txt"))
                                try Data("private".utf8).write(to: directory.appendingPathComponent("private.txt"))
                                return directory
                            })
    }

    @Test("同步只传目标文件，创建嵌套目录，短语原子落盘且清理暂存")
    func successfulSync() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Server()
        let operation = operation(server: server, root: root)
        try await operation.run()
        #expect(await server.uploads.keys.sorted() == ["nested/Rime_Sync/own/luna_pinyin_extended.userdb.txt"])
        #expect(await server.directories == ["nested", "nested/Rime_Sync", "nested/Rime_Sync/own"])
        #expect(try String(contentsOf: root.appendingPathComponent("user/custom_phrase.txt"), encoding: .utf8) == "foreign phrases")
        #expect(!FileManager.default.fileExists(atPath: operation.staging.path))
    }

    @Test("下载失败不能覆盖已有短语、调用引擎或上传")
    func failedDownload() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Server(failDownload: true)
        var operation = operation(server: server, root: root)
        operation = WebDAVSyncOperation(client: operation.client, root: operation.root, installationID: operation.installationID,
                                        staging: operation.staging, userDirectory: operation.userDirectory,
                                        runEngine: { _ in Issue.record("下载失败后不应调用引擎"); throw URLError(.unknown) })
        do { try await operation.run(); Issue.record("应当失败") } catch { }
        #expect(await server.uploads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: operation.staging.path))
    }

    @Test("上传失败必须报错，仍清理暂存目录")
    func failedUpload() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Server(failUpload: true)
        let operation = operation(server: server, root: root)
        do { try await operation.run(); Issue.record("应当失败") } catch { }
        #expect(!FileManager.default.fileExists(atPath: operation.staging.path))
    }
}
