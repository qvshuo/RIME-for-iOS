import Foundation
import Security

/// 共享 Keychain 里存储的 WebDAV 凭据（URL + 用户名 + 密码 + 同步目录）。
/// 主 App 写入，主 App 与键盘扩展通过 `keychain-access-groups` 共享读取。
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

/// WebDAV 凭据的 Keychain 读写。共享 access group `$(AppIdentifierPrefix)art.anjing.quill.shared`，
/// 主 App 与键盘扩展均可访问（自签下 App Identifier Prefix 一致即可）。
///
/// 条目清单（git 历史核查过；卸载重装不清钥匙串，删除须显式覆盖全部名字）：
/// - 凭据：service `art.anjing.quill.webdav` / account `config`
/// - Team 前缀探测（瞬态）：service `…webdav.probe` / account `config`
///
/// 每个条目可能落在共享组或进程默认组，`delete()` 两组都清。
/// 已知边界：键盘进程在无共享组时写入自己默认组的条目，主 App 受钥匙串
/// ACL 限制删不到——凭据只在主 App 写入，实际不受影响。
public enum WebDAVKeychainStore {
    private static let service = "art.anjing.quill.webdav"
    private static let account = "config"

    /// 钥匙串写入失败时携带具体 OSStatus 的原因。
    public enum KeychainError: Error {
        case saveFailed(OSStatus)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 删除条目。必须同时清「共享 group」和「进程默认 group」：自签下共享 group
    /// 不可用、首次保存落到默认 group，只删共享 group 会留下重复条目导致
    /// 第二次保存 `errSecDuplicateItem`。
    private static func delete(service: String, account: String) {
        let base = baseQuery(service: service, account: account)
        // 探测条目中途崩溃会遗留 .probe 残骸，顺手清掉。
        SecItemDelete(baseQuery(service: service + ".probe", account: account) as CFDictionary)
        if let group = resolveAccessGroup(), !group.isEmpty {
            var query = base
            query[kSecAttrAccessGroup as String] = group
            SecItemDelete(query as CFDictionary)
        }
        SecItemDelete(base as CFDictionary)
    }

    public static func delete() {
        delete(service: service, account: account)
    }

    /// 写入 generic password：优先共享 access group，失败回退进程默认 group。
    private static func upsert(service: String, account: String, data: Data) -> OSStatus {
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if let group = resolveAccessGroup(), !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
            let status = SecItemAdd(query as CFDictionary, nil)
            logAddStatus(status, group: group)
            if status == errSecSuccess {
                return status
            }
            // 自签下共享 access group 可能不可用，回退到进程默认 group。
        }
        // 回退前先清一次默认 group 的残留条目，避免 errSecDuplicateItem。
        query[kSecAttrAccessGroup as String] = nil
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        logAddStatus(status, group: nil)
        return status
    }

    /// 读取 generic password 数据：优先共享 access group，回退进程默认 group。
    private static func load(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let group = resolveAccessGroup(), !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data {
                return data
            }
        }
        // 回退：进程默认 group。
        query[kSecAttrAccessGroup as String] = nil
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    public static func save(_ credentials: WebDAVCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        delete(service: service, account: account)
        let status = upsert(service: service, account: account, data: data)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func logAddStatus(_ status: OSStatus, group: String?) {
        let name = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        NSLog("WebDAVKeychain save group=%@ status=%d (%@)", group ?? "(default)", status, name)
    }

    public static func load() -> WebDAVCredentials? {
        guard let data = load(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(WebDAVCredentials.self, from: data)
    }

    /// 解析共享 keychain access group `<TeamID>art.anjing.quill.shared`。
    /// iOS 无公开 API 读自己的 entitlements，改用探测法：写一条不带 access group
    /// 的临时条目再读回，其默认 access group = `<TeamID><bundleID>`，取 bundle ID
    /// 之前的部分作为 Team 前缀。自签探测不到前缀时返回 nil，调用方回退进程默认 group。
    /// 注意后缀匹配用 `art.anjing.quill`：主 App 与键盘扩展（`.keyboard`）的
    /// bundle ID 都以它结尾，同一前缀提取对两个进程都成立。
    private static func resolveAccessGroup() -> String? {
        let probeService = service + ".probe"
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([0x01]),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(probe as CFDictionary)
        guard SecItemAdd(probe as CFDictionary, nil) == errSecSuccess else { return nil }

        let read: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        var group: String?
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
           let attrs = item as? [String: Any],
           let g = attrs[kSecAttrAccessGroup as String] as? String {
            group = g
        }
        SecItemDelete(probe as CFDictionary)

        guard let group else { return nil }
        // 默认 access group = `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`
        // 或自签下就是 bundle ID。取 bundle ID 之前的部分作为 Team 前缀。
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        if group.hasSuffix(bundleID), group.count > bundleID.count {
            let prefix = String(group.dropLast(bundleID.count))
            return prefix + "art.anjing.quill.shared"
        }
        return nil
    }
}
