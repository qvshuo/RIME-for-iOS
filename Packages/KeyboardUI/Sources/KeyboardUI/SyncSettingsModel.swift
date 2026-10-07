import Foundation
import Observation
import KeyboardModels
import RimeSync

@MainActor
@Observable
final class SyncSettingsModel {
    enum Field: Int, CaseIterable, Identifiable {
        case server, username, password, path, installationID
        var id: Self { self }
        var isRequired: Bool {
            switch self {
            case .server, .username, .password: true
            case .path, .installationID: false
            }
        }
        var title: String {
            switch self {
            case .server: "服务器"
            case .username: "用户名"
            case .password: "密码"
            case .path: "同步目录"
            case .installationID: "安装 ID"
            }
        }
        var placeholder: String {
            switch self {
            case .server: "https://…"
            case .username: "WebDAV 用户名"
            case .password: "WebDAV 密码"
            case .path: "Rime_Sync"
            case .installationID: "iPhone"
            }
        }
    }

    var values: [Field: String] = [:]
    var editingField: Field?
    var isTesting = false
    var message: String?
    var isError = false
    var hasSavedCredentials = false
    private var savedValues: [Field: String] = [:]
    var hasUnsavedChanges: Bool { values != savedValues }
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private let store: WebDAVCredentialStore
    @ObservationIgnored private let testConnection: @Sendable (WebDAVCredentials) async throws -> Void

    init(store: WebDAVCredentialStore = .shared,
         testConnection: @escaping @Sendable (WebDAVCredentials) async throws -> Void = { credentials in
             let client = WebDAVClient(credentials: credentials, requestTimeout: 15, resourceTimeout: 15)
             do {
                 _ = try await client.listDirectory(relativePath: credentials.syncPath ?? "Rime_Sync")
             } catch WebDAVClient.WebDAVError.serverError(let code) where code == 404 {
                 // 首次配置的目录尚不存在，由首次同步创建。
             }
         }) {
        self.store = store
        self.testConnection = testConnection
    }

    var allCredentialsEmpty: Bool {
        [Field.server, .username, .password].allSatisfy { values[$0, default: ""].isEmpty }
    }

    func load() {
        guard !didLoad else { return }
        didLoad = true
        do {
            if let credentials = try store.load() {
                values = [.server: credentials.baseURL, .username: credentials.username,
                          .password: credentials.password, .path: credentials.syncPath ?? "",
                          .installationID: credentials.installationID ?? ""]
                savedValues = values
                hasSavedCredentials = true
            }
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    func consume(_ action: KeyAction) {
        guard let field = editingField, !isTesting else { return }
        switch action {
        case .character(let text), .directInput(let text): values[field, default: ""] += text
        case .space: values[field, default: ""] += " "
        case .backspace:
            if !values[field, default: ""].isEmpty { values[field]?.removeLast() }
        case .return:
            editingField = Field(rawValue: field.rawValue + 1)
        default: break
        }
    }

    func append(_ text: String) {
        guard let field = editingField, !isTesting else { return }
        values[field, default: ""] += text
    }

    func clearField() {
        guard let field = editingField, !isTesting else { return }
        values[field] = ""
    }

    func requireFullAccess(_ allowed: Bool) -> Bool {
        guard allowed else {
            show("请在系统设置 → 通用 → 键盘 → 键盘 → RIME for iOS 中开启“允许完全访问”，再重试。", isError: true)
            return false
        }
        return true
    }

    func save(hasFullAccess: Bool = true) async {
        guard !isTesting, (!hasSavedCredentials || hasUnsavedChanges), requireFullAccess(hasFullAccess) else { return }
        do {
            let credentials = try WebDAVCredentials(
                baseURL: values[.server, default: ""], username: values[.username, default: ""],
                password: values[.password, default: ""], syncPath: values[.path], installationID: values[.installationID]
            ).validated()
            message = nil
            isError = false
            isTesting = true
            defer { isTesting = false }
            try await testConnection(credentials)
            try Task.checkCancellation()
            try store.save(credentials)
            savedValues = values
            hasSavedCredentials = true
            show("连接成功，已保存。")
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                show("连接测试超时，请先在 RIME for iOS 主应用中开启联网权限，再检查服务器地址并重试。", isError: true)
            case .notConnectedToInternet, .dataNotAllowed:
                show("网络不可用，请先在 RIME for iOS 主应用中开启联网权限，并检查系统的无线局域网／蜂窝数据权限。", isError: true)
            default:
                show(error.localizedDescription, isError: true)
            }
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    func delete() {
        guard !isTesting else { return }
        do {
            try store.delete()
            values = [:]
            savedValues = [:]
            hasSavedCredentials = false
            show("凭据已删除。")
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ text: String, isError: Bool = false) {
        message = text
        self.isError = isError
    }
}
