import Foundation
import Testing
@testable import Sync

struct WebDAVClientTests {
    @Test("路径逐段编码，拒绝越界路径和非 HTTPS 地址")
    func requestPaths() {
        let client = WebDAVClient(credentials: .init(baseURL: "https://example.com/dav/", username: "u", password: "p"))
        #expect(client.makeURL(relativePath: "词库/a?#%.txt")?.path == "/dav/词库/a?#%.txt")
        for path in ["../escape", "a/../b", "/absolute", "a//b", "a/", "a\\b", ""] {
            #expect(client.makeURL(relativePath: path) == nil)
        }
        let insecure = WebDAVClient(credentials: .init(baseURL: "http://example.com", username: "u", password: "p"))
        #expect(insecure.makeURL(relativePath: "Rime_Sync") == nil)
    }

    @Test("目录列表只接受当前集合的直接子项，正确解码保留字符")
    func directoryEntries() throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Rime_Sync/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Rime_Sync/a%3Fb%25/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Rime_Sync/nested/file</d:href></d:response>
          <d:response><d:href>/dav/Rime_Sync2/other</d:href></d:response>
          <d:response><d:href>https://other.example/dav/Rime_Sync/foreign</d:href></d:response>
        </d:multistatus>
        """
        let parser = PROPFINDParser(xml: xml, basePath: "/dav/Rime_Sync", baseAbsoluteURL: URL(string: "https://example.com/dav/Rime_Sync")!)
        let entries = try parser.parse()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "a?b%")
        #expect(entries.first?.isDirectory == true)
    }

    @Test("损坏的目录响应必须报错，不能当成空目录成功")
    func malformedDirectory() {
        for xml in ["<broken>", "<html><body>Login</body></html>", "<multistatus/>"] {
            let parser = PROPFINDParser(xml: xml, basePath: "/dav", baseAbsoluteURL: URL(string: "https://example.com/dav")!)
            #expect(throws: WebDAVClient.WebDAVError.self) { try parser.parse() }
        }
    }
}
