import Foundation
import KeyboardModels
@preconcurrency import RimeEngineC

extension RimeContext {
    public var isLiteralComposition: Bool {
        lock.lock()
        defer { lock.unlock() }
        return literalComposition != nil
    }

    /// 全角符号不能走 ASCII keycode，否则会提前提交或触发数字选词。
    @discardableResult
    public func appendLiteralInput(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { return false }
        createSessionIfNeeded()
        guard session != 0 else { return false }
        let composition = literalComposition ?? stringOrNil(rimeAPI.get_input!(session)) ?? ""
        if literalComposition == nil { rimeAPI.clear_composition!(session) }
        literalComposition = composition + text
        refreshContext()
        return true
    }

    private func commitLiteralComposition() -> Bool {
        guard let text = literalComposition else { return false }
        literalComposition = nil
        commitText = text
        setContext(candidates: [], preedit: "", highlighted: 0)
        return !text.isEmpty
    }

    @discardableResult
    public func processKey(_ keyCode: Int32, modifier: Int32 = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { return false }
        createSessionIfNeeded()
        guard session != 0, rimeAPI.find_session!(session) else { return false }

        if var text = literalComposition {
            switch keyCode {
            case XK_BackSpace:
                if !text.isEmpty { text.removeLast() }
                literalComposition = text.isEmpty ? nil : text
                refreshContext()
                return true
            case XK_Return:
                return commitLiteralComposition()
            case XK_space:
                return commitLiteralComposition()
            default: return false
            }
        }
        let handled = rimeAPI.process_key!(session, keyCode, modifier)
        // 未命中键不改变 RIME 上下文，跳过 refreshContext 省去热路径开销。
        if handled {
            refreshContext()
        }
        return handled
    }

    @discardableResult
    public func commitComposition() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, session != 0, rimeAPI.find_session!(session) else { return false }

        if literalComposition != nil { return commitLiteralComposition() }
        // 空格可能只被 ASCII 组合接收，不能用按键已处理来判断是否完成上屏。
        let committed = rimeAPI.commit_composition!(session)
        refreshContext()
        return committed
    }

    /// 只在展开时补充候选；按键热路径仅读取当前页。
    public func loadExpandedCandidates() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, session != 0, rimeAPI.find_session!(session) else { return }
        refreshContext(loadAll: true)
    }

    public func selectCandidate(at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, session != 0 else { return }
        if literalComposition != nil {
            if index == 0 { _ = commitLiteralComposition() }
            return
        }
        // 数组下标是全局候选索引，不能使用仅针对当前页的选择 API。
        if !rimeAPI.select_candidate!(session, max(0, index)) {
            log("selectCandidate(\(index)) failed")
        }
        refreshContext()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, session != 0 else { return }
        literalComposition = nil
        rimeAPI.clear_composition!(session)
        // 组合清空时一并丢弃尚未消费的 commit，避免过期文本在下次 pollCommit 冒出。
        commitText = ""
        refreshContext()
    }

    func readSchemaList() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { return [] }
        var list = RimeSchemaList()
        memset(&list, 0, MemoryLayout<RimeSchemaList>.size)
        guard rimeAPI.get_schema_list!(&list) else { return [] }
        var result: [String] = []
        if let items = list.list {
            for i in 0..<list.size {
                result.append(stringOrNil(items[i].schema_id) ?? "")
            }
        }
        rimeAPI.free_schema_list!(&list)
        return result
    }

    public func setAsciiMode(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        pendingAsciiMode = value
        guard isReady, session != 0 else { return }
        rimeAPI.set_option!(session, "ascii_mode", value)
        refreshContext()
    }

    /// 取出并清空一次性提交，重复读取不会再次返回同一段文本。
    public func pollCommit() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let text = commitText
        commitText = ""
        return text.isEmpty ? nil : text
    }

    /// get_commit 是一次性读取，必须先于 context 刷新消费。
    func refreshContext(loadAll: Bool = false) {
        if let text = literalComposition {
            setContext(candidates: text.isEmpty ? [] : [Candidate(text: text)], preedit: text, highlighted: 0)
            return
        }
        guard isReady, session != 0, rimeAPI.find_session!(session) else {
            setContext(candidates: [], preedit: "", highlighted: 0)
            return
        }

        var commit = RimeCommit()
        rimeStructInit(&commit)
        if rimeAPI.get_commit!(session, &commit), let text = stringOrNil(commit.text), !text.isEmpty {
            commitText = text
            _ = rimeAPI.free_commit!(&commit)
            rimeAPI.clear_composition!(session)
            setContext(candidates: [], preedit: "", highlighted: 0)
            return
        }
        _ = rimeAPI.free_commit!(&commit)

        var ctx = RimeContext_stdbool()
        rimeStructInit(&ctx)
        guard rimeAPI.get_context!(session, &ctx) else {
            setContext(candidates: [], preedit: "", highlighted: 0)
            return
        }

        let preedit_text = stringOrNil(ctx.composition.preedit) ?? ""
        let highlighted = Int(ctx.menu.highlighted_candidate_index)

        var candidates: [Candidate] = []
        if let list = ctx.menu.candidates {
            let count = Int(ctx.menu.num_candidates)
            for i in 0..<count {
                let candidate = Candidate(text: stringOrNil(list[i].text) ?? "")
                candidates.append(candidate)
            }
        }
        _ = rimeAPI.free_context!(&ctx)

        // 取满 77 个候选（超出当前页的部分用候选列表迭代器补齐），供展开网格使用。
        // 热路径（loadAll == false）只保留当前页，补齐仅在展开网格时发生。
        var batch = candidates
        if loadAll, batch.count < candidateBatchSize, session != 0 {
            batch.append(contentsOf: candidateList(from: batch.count, count: candidateBatchSize - batch.count))
        }
        setContext(candidates: batch, preedit: preedit_text, highlighted: highlighted)
    }

    func setContext(candidates: [Candidate], preedit: String, highlighted: Int) {
        let action = {
            self.candidates = candidates
            self.preedit = preedit
            self.highlightedCandidateIndex = highlighted
        }
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    private func candidateList(from index: Int, count: Int) -> [Candidate] {
        guard count > 0, session != 0 else { return [] }
        var iterator = RimeCandidateListIterator(ptr: nil, index: 0,
                                                 candidate: RimeCandidate(text: nil, comment: nil, reserved: nil))
        guard rimeAPI.candidate_list_from_index!(session, &iterator, Int32(index)) else { return [] }

        var result: [Candidate] = []
        let maxIndex = index + count
        while rimeAPI.candidate_list_next!(&iterator) {
            if iterator.index >= Int32(maxIndex) { break }
            result.append(Candidate(text: stringOrNil(iterator.candidate.text) ?? ""))
        }
        rimeAPI.candidate_list_end!(&iterator)
        return result
    }
}
