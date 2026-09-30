import Foundation

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

