import Foundation
import Testing
import Synchronization
@testable import Sync

struct SyncCancellationTests {
    private actor Gate {
        private var engine: CheckedContinuation<Void, Never>?
        private var entered = false
        private var entryWaiter: CheckedContinuation<Void, Never>?
        private var cancelled = false
        private var cancelWaiter: CheckedContinuation<Void, Never>?

        func runEngine() async {
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { engine = $0 }
        }
        func waitForEngine() async {
            if entered { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }
        func noteCancellation() {
            cancelled = true
            cancelWaiter?.resume()
            cancelWaiter = nil
        }
        func waitForCancellation() async {
            if cancelled { return }
            await withCheckedContinuation { cancelWaiter = $0 }
        }
        func finishEngine() { engine?.resume(); engine = nil }
    }

    @Test("超时会取消同步，但不能在阻塞引擎退出前返回给 UI")
    func deadlineWaitsForEngineCleanup() async {
        let gate = Gate()
        let finished = Mutex(false)
        let task = Task {
            let result = await WebDAVSync.race(operation: {
                await withTaskCancellationHandler {
                    await gate.runEngine()
                    return true
                } onCancel: {
                    Task { await gate.noteCancellation() }
                }
            }, deadline: { await gate.waitForEngine() })
            finished.withLock { $0 = true }
            return result
        }
        await gate.waitForCancellation()
        #expect(!finished.withLock { $0 })
        await gate.finishEngine()
        #expect(await task.value == false)
        #expect(finished.withLock { $0 })
    }
}
