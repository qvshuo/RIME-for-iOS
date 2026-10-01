import Foundation

/// 候选身份由稳定索引提供，不能用每次刷新都会改变的随机 UUID。
public struct Candidate: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
