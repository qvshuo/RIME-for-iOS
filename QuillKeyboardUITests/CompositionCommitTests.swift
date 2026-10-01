import Foundation
import Testing
import RimeEngineC
import UIKit
import Models
@testable import KeyboardUI
@testable import RimeEngine

@MainActor
struct CompositionCommitTests {
    @Test("大写组合显式提交后清除预输入，上屏文本仅消费一次")
    func uppercaseCompositionBeforeDirectInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let build = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 不加载词典或部署数据，直接测试真实 librime 的大写 ASCII 组合。
        try "schema_list:\n  - schema: regression\n".write(
            to: build.appendingPathComponent("default.yaml"), atomically: true, encoding: .utf8)
        try """
        schema:
          schema_id: regression
          name: Regression
          version: "1"
        engine:
          processors: [ascii_composer, recognizer, speller, express_editor]
          segmentors: [ascii_segmentor, matcher, abc_segmentor, fallback_segmentor]
          translators: [echo_translator]
        speller:
          alphabet: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ
        recognizer:
          patterns:
            uppercase: "[A-Z][-_+.'0-9A-Za-z]*$"
        """.write(to: build.appendingPathComponent("regression.schema.yaml"), atomically: true, encoding: .utf8)

        let engine = RimeContext.shared
        engine.lock.lock()
        defer { engine.lock.unlock() }
        var traits = RimeTraits()
        rimeStructInit(&traits)
        quill_configure_rime_modules(&traits)
        setCString(root.path, to: &traits.shared_data_dir)
        setCString(root.path, to: &traits.user_data_dir)
        setCString(build.path, to: &traits.prebuilt_data_dir)
        setCString(root.path, to: &traits.log_dir)
        engine.rimeAPI.setup!(&traits)
        engine.rimeAPI.initialize!(&traits)
        #expect(engine.rimeAPI.find_module!("lua") != nil)
        #expect(engine.rimeAPI.find_module!("octagram") != nil)
        engine.isReady = true
        engine.session = engine.rimeAPI.create_session!()
        defer {
            engine.destroySession()
            engine.isReady = false
            engine.commitText = ""
            engine.setContext(candidates: [], preedit: "", highlighted: 0)
            engine.rimeAPI.finalize!()
        }
        #expect(engine.rimeAPI.select_schema!(engine.session, "regression"))

        for text in ["A", "AB", "ABC"] {
            for character in text.utf8 {
                #expect(engine.processKey(Int32(character)))
            }
            #expect(engine.preedit == text)
            #expect(engine.pollCommit() == nil)
            #expect(engine.commitComposition())
            let committed = try #require(engine.pollCommit())
            #expect(committed == text)
            #expect(engine.preedit.isEmpty)
            #expect(engine.pollCommit() == nil)
            #expect(!engine.commitComposition())
        }

        #expect(engine.processKey(65))
        engine.setAsciiMode(true)
        #expect(engine.processKey(32))
        #expect(engine.pollCommit() == nil)
        #expect(!engine.preedit.isEmpty)
        #expect(engine.commitComposition())
        #expect(engine.pollCommit() == "A ")
        #expect(engine.preedit.isEmpty)
        engine.setAsciiMode(false)

        // 完整覆盖 shift → 大写组合 → 数字/符号，并使用真实 UITextView 宿主。
        for locked in [false, true] {
            for (layout, suffix) in [(KeyAction.numbers, "1"), (.symbols, "！")] {
                let model = KeyboardViewModel()
                _ = model.consume(.shift)
                if locked { _ = model.consume(.shift) }
                #expect(model.consume(.character("a")) == .character("A"))
                #expect(engine.processKey(65))
                let proxy = TextViewProxy()
                proxy.keepsCursorAtMarkedStart = true
                proxy.setMarkedText(engine.preedit, selectedRange: NSRange(location: engine.preedit.utf16.count, length: 0))
                _ = model.consume(layout)
                #expect(model.consume(.character(suffix)) == .directInput(suffix))
                MarkedTextWriter.finishComposition(appending: suffix, from: engine, replacingMarkedText: true, to: proxy)
                #expect(proxy.textView.text == "A" + suffix)
                #expect(proxy.insertions == ["A" + suffix])
                #expect(proxy.textView.markedTextRange == nil)
                #expect(engine.preedit.isEmpty)
                #expect(engine.pollCommit() == nil)
            }
        }
    }
}
