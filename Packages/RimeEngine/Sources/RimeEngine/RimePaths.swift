import Foundation

/// 无 App Group 时使用各进程私有目录，主应用与扩展无法共享数据。
public enum RimePaths {
    public static let appGroupID = "group.art.anjing.rimeios"

    public static var appGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// 扩展的 Bundle.main 是 .appex，需回溯宿主应用读取 SharedSupport。
    public static var sharedSupportDirectory: URL? {
        var candidates: [Bundle] = [Bundle.main]
        if let main = Bundle.main.resourceURL {
            let appBundle = main.deletingLastPathComponent().deletingLastPathComponent()
            if let bundle = Bundle(url: appBundle) {
                candidates.append(bundle)
            }
        }
        if let execPath = Bundle.main.executableURL {
            let appex = execPath.deletingLastPathComponent()
            let hostApp = appex.deletingLastPathComponent().deletingLastPathComponent()
            if let bundle = Bundle(url: hostApp) {
                candidates.append(bundle)
            }
        }
        for bundle in candidates {
            if let url = bundle.url(forResource: "SharedSupport", withExtension: nil) {
                return url
            }
        }
        return nil
    }

    public static var userDataDirectory: URL? {
        if let group = appGroupContainer {
            return group.appendingPathComponent("Rime", isDirectory: true)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("RIMEForiOS/Rime", isDirectory: true)
        }
        return nil
    }

    public static var logDirectory: URL? {
        let base: URL?
        if let group = appGroupContainer {
            base = group
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        guard let base else { return nil }
        let url = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var syncDirectory: URL? {
        userDataDirectory?.appendingPathComponent("sync", isDirectory: true)
    }
}
