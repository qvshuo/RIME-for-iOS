import Foundation

/// 共享 Keychain 里存储的 WebDAV 凭据（URL + 用户名 + 密码 + 同步目录）。
/// 键盘扩展读写，主 App 自签下与键盘沙盒隔离、不再承担凭据存储。
public struct WebDAVCredentials: Codable, Equatable, Sendable {
    public let baseURL: String
    public let username: String
    public let password: String
    /// 远程同步目录相对路径（相对 baseURL），如 `Rime_Sync`。nil 表示使用默认值。
    public let syncPath: String?
    /// 本机安装 ID（WebDAV 下 `同步目录/<installationID>/` 子目录名）。nil 表示使用默认值 "Quill"。
    public let installationID: String?

    public init(baseURL: String, username: String, password: String, syncPath: String? = nil, installationID: String? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.syncPath = syncPath
        self.installationID = installationID
    }

    /// 根 URL 保证以 `/` 结尾，方便拼接同步目录路径。
    public var normalizedBaseURL: String {
        baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
    }
}

/// WebDAV 凭据的文件存储（JSON 落盘）。键盘扩展私有目录：
/// 有 App Group 时 `group.art.anjing.quill/WebDAVCredentials.json`，
/// 否则 `Application Support/Quill/WebDAVCredentials.json`。
/// 自签下主 App 与键盘各自独立，凭据只在键盘进程读写；JSON 的密码字段
/// 用 Base64 包裹做最低限度混淆（防随手翻阅，非加密——沙盒即边界）。
public enum WebDAVCredentialStore {
    /// 凭据文件 URL；目录不可用时返回 nil（同步层据此视为无凭据）。
    private static var fileURL: URL? {
        let base: URL?
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.art.anjing.quill"
        ) {
            base = group
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Quill", isDirectory: true)
        }
        return base?.appendingPathComponent("WebDAVCredentials.json")
    }

    /// 密码字段的 Base64 包裹（落盘混淆；读写对称）。
    private struct StoredCredentials: Codable {
        let baseURL: String
        let username: String
        let password: String
        let syncPath: String?
        let installationID: String?
    }

    public static func save(_ credentials: WebDAVCredentials) throws {
        guard let url = fileURL else { return }
        let stored = StoredCredentials(
            baseURL: credentials.baseURL,
            username: credentials.username,
            password: Data(credentials.password.utf8).base64EncodedString(),
            syncPath: credentials.syncPath,
            installationID: credentials.installationID
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: .atomic)
    }

    public static func load() -> WebDAVCredentials? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data),
              let passwordData = Data(base64Encoded: stored.password),
              let password = String(data: passwordData, encoding: .utf8)
        else { return nil }
        return WebDAVCredentials(
            baseURL: stored.baseURL,
            username: stored.username,
            password: password,
            syncPath: stored.syncPath,
            installationID: stored.installationID
        )
    }

    public static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
