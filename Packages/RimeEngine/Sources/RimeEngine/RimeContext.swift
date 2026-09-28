import Foundation
import Observation
import Models
@preconcurrency import RimeEngineC

/// 进程内单例 RIME 上下文：Swift 直接持有 `RimeApi_stdbool` 调用 librime C API。
///
/// 生命周期：每进程只 `start()` 一次（setup → initialize，不 deploy），setup 完成
/// 前 `processKey` 丢键。方法按职责拆在 `RimeContext+*.swift`；本文件只保留声明
/// 与共享内部状态。librime 非线程安全：所有 C API 调用都持 `lock` 执行。
@Observable
public final class RimeContext: @unchecked Sendable {
    public static let shared = RimeContext()

    // MARK: - librime direct bridge

    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool()!.pointee
    let lock = NSRecursiveLock()

    var isSetup = false
    var isStarting = false
    /// setup 完成、可以处理按键。
    var isReady = false
    var session: RimeSessionId = 0
    /// 会话创建后应写入的 `ascii_mode` 初始值；会话未创建时先 pending。
    /// `.asciiCapable` 字段需要英文模式，`.default` 需要中文模式。
    var pendingAsciiMode: Bool = false

    /// 每次刷新一次性取回的候选数（初始直接 77，支持展开网格）。
    let candidateBatchSize = 77

    // MARK: - Observable state

    public internal(set) var candidates: [Candidate] = []
    public internal(set) var preedit: String = ""
    public internal(set) var highlightedCandidateIndex: Int = 0
    /// 一次性 commit 缓冲：只经 `pollCommit()` 消费。`@ObservationIgnored`：
    /// 持锁下由任意线程写入，不走「只在主线程写」的可观察通道。
    @ObservationIgnored public internal(set) var commitText: String = ""

    let logFileName = "quill.log"
    let keyboardLogFileName = "keyboard.log"

    private init() {}
}

extension RimeContext {
    public enum RimeError: Error, LocalizedError {
        case missingDirectory
        case syncFailed

        public var errorDescription: String? {
            switch self {
            case .missingDirectory: return "无法定位 RIME 数据目录"
            case .syncFailed: return "同步失败"
            }
        }
    }
}
