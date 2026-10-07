import Foundation
import Testing
import Synchronization
import KeyboardModels
@testable import RimeSync
@testable import KeyboardUI

@MainActor
struct SyncSettingsTests {
    private func store() -> WebDAVCredentialStore {
        WebDAVCredentialStore(fileURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("credentials.json"))
    }

    @Test("字段编辑只修改草稿，退格按完整字符删除，回车切换下一项")
    func draftEditing() {
        let model = SyncSettingsModel(store: store())
        model.editingField = .username
        model.consume(.character("👨‍👩‍👧‍👦"))
        model.consume(.backspace)
        #expect(model.values[.username] == "")
        model.consume(.directInput("Alice"))
        model.consume(.return)
        #expect(model.editingField == .password)
        #expect(model.values[.username] == "Alice")
        model.consume(.character("secret"))
        model.editingField = .installationID
        model.consume(.return)
        #expect(model.editingField == nil)
        model.consume(.character("must not appear"))
        #expect(model.values[.installationID] == nil)
    }

    @Test("测试成功才保存；服务器规范化且密码保留空格")
    func successfulSave() async throws {
        let storage = store()
        defer { try? storage.delete() }
        let requests = Mutex(0)
        let model = SyncSettingsModel(store: storage, testConnection: { _ in requests.withLock { $0 += 1 } })
        model.values = [.server: " example.com/dav ", .username: " Alice ", .password: " p "]
        await model.save()
        let saved = try #require(try storage.load())
        #expect(saved.baseURL == "https://example.com/dav")
        #expect(saved.username == "Alice")
        #expect(saved.password == " p ")
        #expect(model.hasSavedCredentials)
        #expect(!model.hasUnsavedChanges)
        #expect(!model.isError)
        #expect(!model.isTesting)
        await model.save()
        #expect(requests.withLock { $0 } == 1)
        model.values[.username] = "Updated"
        await model.save()
        #expect(requests.withLock { $0 } == 2)
        #expect(!model.hasUnsavedChanges)
        model.delete()
        #expect(try storage.load() == nil)
        #expect(model.values.isEmpty)
        #expect(!model.hasSavedCredentials)
    }

    @Test("连接失败保留旧凭据和编辑草稿")
    func failedSave() async throws {
        let storage = store()
        defer { try? storage.delete() }
        let original = WebDAVCredentials(baseURL: "https://old.example", username: "old", password: "old")
        try storage.save(original)
        let model = SyncSettingsModel(store: storage, testConnection: { _ in throw URLError(.cannotConnectToHost) })
        model.load()
        model.values[.server] = "new.example"
        await model.save()
        #expect(try storage.load() == original)
        #expect(model.values[.server] == "new.example")
        #expect(model.hasUnsavedChanges)
        #expect(model.isError)
        #expect(!model.isTesting)
        model.load()
        #expect(model.values[.server] == "new.example")
    }

    @Test("无完全访问权限时不联网、不保存，也不进入测试中")
    func missingFullAccess() async throws {
        let storage = store()
        let model = SyncSettingsModel(store: storage, testConnection: { _ in Issue.record("不应联网") })
        model.values = [.server: "https://example.com", .username: "u", .password: "p"]
        await model.save(hasFullAccess: false)
        #expect(!model.isTesting)
        #expect(model.isError)
        #expect(model.message?.contains("允许完全访问") == true)
        #expect(try storage.load() == nil)
    }

    @Test("连接超时或网络被禁止时结束测试并保留草稿")
    func unavailableNetwork() async throws {
        for code in [URLError.Code.timedOut, .notConnectedToInternet, .dataNotAllowed] {
            let storage = store()
            let model = SyncSettingsModel(store: storage, testConnection: { _ in throw URLError(code) })
            let draft: [SyncSettingsModel.Field: String] = [.server: "https://example.com", .username: "u", .password: "p"]
            model.values = draft
            await model.save()
            #expect(!model.isTesting)
            #expect(model.isError)
            #expect(model.message?.contains(code == .timedOut ? "超时" : "网络不可用") == true)
            #expect(model.values == draft)
            #expect(try storage.load() == nil)
        }
    }

    @Test("非法配置不发起连接，也不写入文件")
    func invalidSave() async throws {
        let storage = store()
        let model = SyncSettingsModel(store: storage, testConnection: { _ in Issue.record("不应测试连接") })
        model.values = [.server: "http://example.com", .username: "u", .password: "p"]
        await model.save()
        #expect(model.isError)
        #expect(try storage.load() == nil)
    }

    @Test("凭据往返与删除，空目录采用默认值")
    func credentialRoundTrip() throws {
        let storage = store()
        defer { try? storage.delete() }
        let credentials = try WebDAVCredentials(baseURL: "example.com", username: "u", password: "秘密🔐", syncPath: " ", installationID: " ").validated()
        try storage.save(credentials)
        #expect(try storage.load() == credentials)
        #expect(credentials.syncPath == nil)
        #expect(credentials.installationID == nil)
        try storage.delete()
        #expect(try storage.load() == nil)
    }

    @Test("拒绝不安全目录、带认证与查询串的服务器地址")
    func validation() {
        for server in ["http://example.com", "https://u:p@example.com", "https://example.com?x=1", "https://example.com/#fragment"] {
            #expect(throws: WebDAVCredentials.ValidationError.self) {
                try WebDAVCredentials(baseURL: server, username: "u", password: "p").validated()
            }
        }
        for id in ["../other", "a/b", "a\\b", ".", ".."] {
            #expect(throws: WebDAVCredentials.ValidationError.self) {
                try WebDAVCredentials(baseURL: "https://example.com", username: "u", password: "p", installationID: id).validated()
            }
        }
    }
}
