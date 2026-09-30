import Foundation

protocol WebDAVTransport: Sendable {
    func listDirectory(relativePath: String) async throws -> [WebDAVClient.Entry]
    func download(relativePath: String) async throws -> Data
    func upload(relativePath: String, data: Data) async throws
    func createDirectory(relativePath: String) async throws
}

extension WebDAVClient: WebDAVTransport {}

/// 文件编排独立于 librime 与凭据存储，便于验证失败和取消时的真实行为。
struct WebDAVSyncOperation: Sendable {
    let client: any WebDAVTransport
    let root: String
    let installationID: String
    let staging: URL
    let userDirectory: URL
    let runEngine: @Sendable (URL) async throws -> URL
    var log: @Sendable (String) -> Void = { _ in }

    private static let files = Set(["luna_pinyin_extended.userdb.txt", "custom_phrase.txt"])

    func run() async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let devices: [String]
        do {
            devices = try await client.listDirectory(relativePath: root)
                .filter { $0.isDirectory && $0.name != installationID }
                .map(\.name).sorted()
        } catch WebDAVClient.WebDAVError.serverError(let code) where code == 404 {
            devices = []
        }
        guard devices.allSatisfy({ WebDAVClient.isSafeRelativePath($0) && !$0.contains("/") }) else {
            throw WebDAVClient.WebDAVError.invalidResponse
        }
        // 两台设备并行下载，限制同时驻留的词库数据，兼顾慢 WebDAV 与扩展内存预算。
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = devices.makeIterator()
            for _ in 0..<2 {
                if let device = iterator.next() { group.addTask { try await download(device) } }
            }
            while try await group.next() != nil {
                if let device = iterator.next() { group.addTask { try await download(device) } }
            }
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        // librime 只合并 userdb；短语沿用远端覆盖语义，按设备名排序保证结果确定。
        for device in devices {
            let source = staging.appendingPathComponent(device).appendingPathComponent("custom_phrase.txt")
            if FileManager.default.fileExists(atPath: source.path) {
                try Data(contentsOf: source).write(to: userDirectory.appendingPathComponent("custom_phrase.txt"), options: .atomic)
            }
        }
        // 应用短语后必须完成引擎维护与重建，即使网络超时也等待此步骤退出。
        let ownDirectory = try await runEngine(staging)
        try Task.checkCancellation()
        var parent = ""
        for component in root.split(separator: "/") {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            try await client.createDirectory(relativePath: parent)
        }
        try await client.createDirectory(relativePath: "\(root)/\(installationID)")
        let exports = try FileManager.default.contentsOfDirectory(at: ownDirectory, includingPropertiesForKeys: nil)
        for file in exports.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where Self.files.contains(file.lastPathComponent) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: file)
            try await client.upload(relativePath: "\(root)/\(installationID)/\(file.lastPathComponent)", data: data)
            log("uploaded \(installationID)/\(file.lastPathComponent) (\(data.count) bytes)")
        }
    }

    private func download(_ device: String) async throws {
        let remote = "\(root)/\(device)"
        let entries = try await client.listDirectory(relativePath: remote)
        for file in entries where !file.isDirectory && Self.files.contains(file.name) {
            try Task.checkCancellation()
            let data = try await client.download(relativePath: "\(remote)/\(file.name)")
            let folder = staging.appendingPathComponent(device)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(file.name), options: .atomic)
            log("downloaded \(device)/\(file.name) (\(data.count) bytes)")
        }
    }
}
