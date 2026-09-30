import Foundation

public extension WebDAVCredentials {
    enum ValidationError: Error, LocalizedError {
        case missingFields, invalidServer, invalidPath, invalidInstallationID

        public var errorDescription: String? {
            switch self {
            case .missingFields: "请填写服务器地址、用户名和密码。"
            case .invalidServer: "请填写有效的 HTTPS 服务器地址。"
            case .invalidPath: "同步目录须为相对路径，不能包含空路径、. 或 ..。"
            case .invalidInstallationID: "安装 ID 须为单个目录名，不能包含 /、\\ 或控制字符。"
            }
        }
    }

    func validated() throws -> WebDAVCredentials {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !user.isEmpty, !password.isEmpty else { throw ValidationError.missingFields }
        let address = raw.contains("://") ? raw : "https://" + raw
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ValidationError.invalidServer
        }
        let path = syncPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let id = installationID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard WebDAVClient.isSafeRelativePath(path.isEmpty ? "Rime_Sync" : path) else { throw ValidationError.invalidPath }
        guard WebDAVClient.isSafeRelativePath(id.isEmpty ? "Quill" : id), !id.contains("/") else {
            throw ValidationError.invalidInstallationID
        }
        return WebDAVCredentials(baseURL: url.absoluteString, username: user, password: password,
                                 syncPath: path.isEmpty ? nil : path, installationID: id.isEmpty ? nil : id)
    }
}
