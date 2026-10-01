import Foundation
import RimeEngineC

/// librime 依据 data_size 判断可选字段；C 结构必须经 rimeStructInit 初始化。
public protocol DataSizeable {
    var data_size: Int32 { get set }
}

public func rimeStructInit<T: DataSizeable>(_ value: inout T) {
    _ = withUnsafeMutableBytes(of: &value) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    value.data_size = Int32(MemoryLayout<T>.size - MemoryLayout<Int32>.size)
}

/// traits 持有这些指针至进程结束，不能在 setup 返回后释放。
@discardableResult
public func setCString(_ value: String?, to target: inout UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = UnsafePointer(duplicated)
    return target
}

@discardableResult
public func setCString(_ value: String?, to target: inout UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = duplicated
    return target
}

public func stringOrNil(_ pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
}

extension RimeTraits: DataSizeable {}
extension RimeCommit: DataSizeable {}
extension RimeContext_stdbool: DataSizeable {}
