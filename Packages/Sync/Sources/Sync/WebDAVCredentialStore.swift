import Foundation
import RimeEngine
import Synchronization

/// 不依赖签名团队的凭据存储。文件受 iOS 数据保护约束，并排除系统备份。
public final class WebDAVCredentialStore: Sendable {
    public static let shared = WebDAVCredentialStore(fileURL:
        (Paths.appGroupContainer ?? URL.applicationSupportDirectory.appendingPathComponent("Quill"))
            .appendingPathComponent("WebDAVCredentials.json")
    )

    private let fileURL: URL
    private let lock = Mutex(())

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ credentials: WebDAVCredentials) throws {
        try lock.withLock { _ in
            let data = try JSONEncoder().encode(credentials)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Base64 不提供保密性；直接依赖文件权限与系统数据保护，不伪装成加密。
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
    }

    public func load() throws -> WebDAVCredentials? {
        try lock.withLock { _ in
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return try JSONDecoder().decode(WebDAVCredentials.self, from: Data(contentsOf: fileURL))
        }
    }

    public func delete() throws {
        try lock.withLock { _ in
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
