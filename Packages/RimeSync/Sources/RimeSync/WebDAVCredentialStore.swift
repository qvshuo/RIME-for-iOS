import Foundation
import RimeEngine
import Synchronization

/// 凭据依赖系统文件保护与 0600 权限，排除备份；没有应用层加密。
public final class WebDAVCredentialStore: Sendable {
    public static let shared = WebDAVCredentialStore(fileURL:
        (RimePaths.appGroupContainer ?? URL.applicationSupportDirectory.appendingPathComponent("RIMEForiOS"))
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
