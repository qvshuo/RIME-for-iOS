import Foundation
import Observation
import KeyboardModels
import Synchronization
@preconcurrency import RimeEngineC

/// 引擎操作持锁串行执行，UI 状态仅在主线程发布；不在扩展内部署。
@Observable
public final class RimeContext: @unchecked Sendable {
    public static let shared = RimeContext()

    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool()!.pointee
    let lock = NSRecursiveLock()
    private let sessionOwner = Mutex<UUID?>(nil)

    @ObservationIgnored var isSetup = false
    @ObservationIgnored var isStarting = false
    @ObservationIgnored var isReady = false
    @ObservationIgnored var session: RimeSessionId = 0
    @ObservationIgnored var literalComposition: String?
    @ObservationIgnored var pendingAsciiMode: Bool = false

    let candidateBatchSize = 77

    public internal(set) var candidates: [Candidate] = []
    public internal(set) var preedit: String = ""
    public internal(set) var highlightedCandidateIndex: Int = 0
    /// commit 只能经 pollCommit 消费；缓冲不参与 UI Observation。
    @ObservationIgnored public internal(set) var commitText: String = ""

    let logURL = RimePaths.logDirectory?.appendingPathComponent("engine.log")

    public func claimSession(_ owner: UUID) {
        sessionOwner.withLock { $0 = owner }
    }

    /// 旧控制器的排队清理不能销毁新控制器接管的会话。
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
