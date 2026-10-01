import Foundation
import Testing
@testable import KeyboardUI

@MainActor
struct ShiftTapTests {
    @Test("单击切换、双击锁定及再次单击解除锁定")
    func shiftTransitions() {
        let model = KeyboardInputModel()
        var date = Date(timeIntervalSince1970: 1000)
        model.now = { date }
        _ = model.consume(.shift)
        #expect(model.shiftState == .uppercaseOnce)
        date += 1
        _ = model.consume(.shift)
        #expect(model.shiftState == .lowercase)
        date += 1
        _ = model.consume(.shift)
        date += 0.1
        _ = model.consume(.shift)
        #expect(model.shiftState == .uppercaseLocked)
        date += 1
        _ = model.consume(.shift)
        #expect(model.shiftState == .lowercase)
    }
}
