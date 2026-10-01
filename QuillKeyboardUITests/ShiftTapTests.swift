import Foundation
import Testing
import UIKit
import Models
@testable import KeyboardUI

/// 大小写 shift 单/双击状态机测试（经公开的 `consume(.shift)` 驱动，
/// 用注入时钟使双击时序确定）。
@MainActor
struct ShiftTapTests {
    /// 可变时钟：测试里推进 `date` 即可控制双击判定的时序。
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1000)
    }

    private func makeModel(_ clock: Clock) -> KeyboardViewModel {
        let model = KeyboardViewModel()
        model.now = { clock.date }
        return model
    }

    @Test("单击进入一次大写，间隔足够后单击取消")
    func singleTapTogglesUppercaseOnce() {
        let clock = Clock()
        let model = makeModel(clock)

        _ = model.consume(.shift)
        #expect(model.shiftState == .uppercaseOnce)

        clock.date += 1 // 超过 0.35s 双击窗口，视为单击
        _ = model.consume(.shift)
        #expect(model.shiftState == .lowercase)
    }

    @Test("0.35s 内两次按下锁定大写")
    func doubleTapLocksUppercase() {
        let clock = Clock()
        let model = makeModel(clock)

        _ = model.consume(.shift)
        clock.date += 0.1
        _ = model.consume(.shift)
        #expect(model.shiftState == .uppercaseLocked)
    }

    @Test("锁定后单击取消锁定")
    func singleTapAfterLockedUnlocks() {
        let clock = Clock()
        let model = makeModel(clock)

        _ = model.consume(.shift)
        clock.date += 0.1
        _ = model.consume(.shift)
        #expect(model.shiftState == .uppercaseLocked)

        clock.date += 1 // 超过双击窗口，视为单击
        _ = model.consume(.shift)
        #expect(model.shiftState == .lowercase)
    }
}