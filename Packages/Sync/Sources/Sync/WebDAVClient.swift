import Foundation

/// 轻量 WebDAV 客户端。只实现本项目需要的操作：
/// PROPFIND（列目录）、GET（下载）、PUT（上传）、MKCOL（建目录）。
/// 认证使用 Basic Auth（Koofr WebDAV 支持）。
public final class WebDAVClient: Sendable {
    public enum WebDAVError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case notAuthenticated
        case serverError(statusCode: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL 无效"
            case .invalidResponse: return "服务器返回了无效的目录列表"
            case .notAuthenticated: return "未认证（用户名/密码错误）"
            case .serverError(let code): return "服务器错误（HTTP \(code)）"
            }
        }
    }

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let isDirectory: Bool
    }

    private let credentials: WebDAVCredentials
    private let session: URLSession

    public init(credentials: WebDAVCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - 基础请求

    private var authHeader: String {
        let data = Data("\(credentials.username):\(credentials.password)".utf8)
        return "Basic \(data.base64EncodedString())"
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\")
                && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }

    func makeURL(relativePath: String) -> URL? {
        guard Self.isSafeRelativePath(relativePath),
              let base = URL(string: credentials.normalizedBaseURL),
              base.scheme?.lowercased() == "https", base.host != nil,
              base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { return nil }
        return relativePath.split(separator: "/").reduce(base) {
            $0.appendingPathComponent(String($1))
        }
    }

    /// 统一请求执行：打 auth 头、区分 data/upload、把非 HTTP 响应、401/403 与
    /// 未通过 `accepted` 的状态码转成 `WebDAVError`。各操作只关心自己的成功条件。
    private func perform(
        _ request: URLRequest,
        uploadData: Data? = nil,
        accepted: (Int) -> Bool
    ) async throws -> Data {
        var request = request
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let result: (Data, URLResponse)
        if let uploadData {
            result = try await session.upload(for: request, from: uploadData)
        } else {
            result = try await session.data(for: request)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw WebDAVError.serverError(statusCode: -1)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.notAuthenticated
        }
        guard accepted(http.statusCode) else {
            throw WebDAVError.serverError(statusCode: http.statusCode)
        }
        return result.0
    }

    // MARK: - 目录列表

    /// 列出 `relativePath`（如 `Rime_Sync/`）下的一级子项。
    public func listDirectory(relativePath: String) async throws -> [Entry] {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>
        """
        request.httpBody = Data(body.utf8)

        let data = try await perform(request) { (200..<300).contains($0) }
        let basePath = url.path
        return try parseMultiStatus(data: data, basePath: basePath, baseAbsoluteURL: url)
    }

    // MARK: - 下载

    public func download(relativePath: String) async throws -> Data {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        let request = URLRequest(url: url)
        return try await perform(request) { $0 == 200 }
    }

    // MARK: - 上传

    public func upload(relativePath: String, data: Data) async throws {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request, uploadData: data) { (200..<300).contains($0) }
    }

    // MARK: - 建目录

    public func createDirectory(relativePath: String) async throws {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        // 405 = 已存在，视为成功。
        _ = try await perform(request) { $0 == 201 || $0 == 405 || (200..<300).contains($0) }
    }

    // MARK: - PROPFIND 响应解析

    /// 解析 WebDAV multistatus XML，返回 `relativePath` 下的一级子项。
    /// `basePath` 用于去掉服务器返回的绝对路径前缀，只保留相对名。
    private func parseMultiStatus(data: Data, basePath: String, baseAbsoluteURL: URL) throws -> [Entry] {
        guard let xml = String(data: data, encoding: .utf8) else { throw WebDAVError.invalidResponse }
        let parser = PROPFINDParser(xml: xml, basePath: basePath, baseAbsoluteURL: baseAbsoluteURL)
        return try parser.parse()
    }
}

/// 极简 PROPFIND XML 解析：只认 `<response><href>…</href>…<resourcetype><collection/></resourcetype></response>`。
final class PROPFINDParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let basePath: String
    private let baseAbsoluteURL: URL

    private var sawMultiStatus = false
    private var currentHref: String?
    private var isInHref = false
    private var isInResourceType = false
    private var isCollection = false
    private var entries: [WebDAVClient.Entry] = []

    init(xml: String, basePath: String, baseAbsoluteURL: URL) {
        self.parser = XMLParser(data: Data(xml.utf8))
        self.basePath = basePath
        self.baseAbsoluteURL = baseAbsoluteURL
        super.init()
        self.parser.shouldProcessNamespaces = true
        self.parser.delegate = self
    }

    func parse() throws -> [WebDAVClient.Entry] {
        guard parser.parse(), sawMultiStatus else { throw WebDAVClient.WebDAVError.invalidResponse }
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch local {
        case "multistatus":
            sawMultiStatus = namespaceURI == "DAV:"
        case "href":
            isInHref = true
            currentHref = ""
        case "resourcetype":
            isInResourceType = true
        case "collection":
            if isInResourceType {
                isCollection = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInHref {
            currentHref = (currentHref ?? "") + string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch local {
        case "href":
            isInHref = false
        case "resourcetype":
            isInResourceType = false
        case "response":
            if let href = currentHref, let name = relativeName(fromHref: href), !name.isEmpty {
                entries.append(WebDAVClient.Entry(name: name, isDirectory: isCollection))
            }
            currentHref = nil
            isCollection = false
        default:
            break
        }
    }

    /// 把服务器返回的 href 转成相对路径。href 可能是绝对 URL、绝对路径、或相对路径。
    private func relativeName(fromHref href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed, relativeTo: baseAbsoluteURL.appendingPathComponent(""))?.absoluteURL,
              url.host == baseAbsoluteURL.host else { return nil }
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        let path = url.path
        guard path.hasPrefix(base) else { return nil }
        let name = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard WebDAVClient.isSafeRelativePath(name), !name.contains("/") else { return nil }
        return name
    }
}
