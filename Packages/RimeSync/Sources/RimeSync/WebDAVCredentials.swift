import Foundation

public struct WebDAVCredentials: Codable, Equatable, Sendable {
    public let baseURL: String
    public let username: String
    public let password: String
    /// nil 使用默认远程目录 Rime_Sync。
    public let syncPath: String?
    /// nil 使用默认设备 ID iPhone；不同设备必须使用不同 ID。
    public let installationID: String?

    public init(baseURL: String, username: String, password: String, syncPath: String? = nil, installationID: String? = nil) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.syncPath = syncPath
        self.installationID = installationID
    }

    public var normalizedBaseURL: String {
        baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
    }
}
