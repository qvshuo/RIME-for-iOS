import Foundation
import Observation
import Models
import Synchronization
@preconcurrency import RimeEngineC

/// librime 的进程内入口。引擎操作持锁串行执行，UI 状态在主线程发布。
/// 只加载随包预构建的数据，避免运行时部署超过键盘扩展的内存预算。
@Observable
public final class RimeContext: @unchecked Sendable {
    public static let shared = RimeContext()

    // MARK: - librime direct bridge

    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool()!.pointee
    let lock = NSRecursiveLock()
    private let sessionOwner = Mutex<UUID?>(nil)

    @ObservationIgnored var isSetup = false
    @ObservationIgnored var isStarting = false
    /// setup 完成、可以处理按键。
    @ObservationIgnored var isReady = false
    @ObservationIgnored var session: RimeSessionId = 0
    /// 会话创建后应写入的 `ascii_mode` 初始值；会话未创建时先 pending。
    /// `.asciiCapable` 字段需要英文模式，`.default` 需要中文模式。
    @ObservationIgnored var pendingAsciiMode: Bool = false

    /// 展开网格时的候选上限；按键热路径只读取当前页。
    let candidateBatchSize = 77

    // MARK: - Observable state

    public internal(set) var candidates: [Candidate] = []
    public internal(set) var preedit: String = ""
    public internal(set) var highlightedCandidateIndex: Int = 0
    /// 一次性 commit 缓冲：只经 `pollCommit()` 消费。`@ObservationIgnored`：
    /// 持锁下由任意线程写入，不走「只在主线程写」的可观察通道。
    @ObservationIgnored public internal(set) var commitText: String = ""

    let logFileName = "quill.log"

    public func claimSession(_ owner: UUID) {
        sessionOwner.withLock { $0 = owner }
    }

    /// 旧控制器的排队清理不能销毁已被新控制器接管的会话。
    public func releaseSession(_ owner: UUID) {
        sessionOwner.withLock { current in
            guard current == owner else { return }
            current = nil
            destroySession()
        }
    }

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
