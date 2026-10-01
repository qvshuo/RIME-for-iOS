import Foundation
import Testing
import RimeEngineC
import UIKit
import Models
@testable import KeyboardUI
@testable import RimeEngine

@MainActor
struct CompositionCommitTests {
    @Test("大写混合组合仅显式确认时提交，兼容原生 RIME")
    func literalCompositionAndNativeCommits() throws {
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

        // 手动大写启动字面组合，数字、全角符号和恢复小写都不能提前提交。
        for locked in [false, true] {
            for language in [InputLanguage.chinese, .english] {
                for first in ["a", "1", "！"] {
                    let model = KeyboardViewModel()
                    model.inputLanguage = language
                    _ = model.consume(.shift)
                    if locked { _ = model.consume(.shift) }
                    let proxy = TextViewProxy()
                    proxy.keepsCursorAtMarkedStart = true
                    var expected = ""
                    for character in [first, "2", "？", "b", "👩🏽‍💻"] {
                        _ = model.consume(character == "a" || character == "b" ? .letters : .numbers)
                        if character == "b" { model.shiftState = .lowercase }
                        let action = try #require(model.consume(.character(character), rimeContext: engine))
                        guard case .composingInput(let text) = action else {
                            Issue.record("字符提前上屏: \(action)")
                            continue
                        }
                        expected += text
                        #expect(engine.appendLiteralInput(text))
                        #expect(engine.preedit == expected)
                        #expect(engine.candidates.map(\.text) == [expected])
                        #expect(engine.pollCommit() == nil)
                        proxy.setMarkedText(expected, selectedRange: NSRange(location: expected.utf16.count, length: 0))
                        #expect(proxy.insertions.isEmpty)
                    }
                    let session = engine.session
                    engine.recreateSession()
                    #expect(engine.session == session)
                    #expect(engine.preedit == expected)
                    #expect(engine.processKey(XK_BackSpace))
                    expected.removeLast()
                    #expect(engine.preedit == expected)
                    if first == "a" {
                        #expect(model.consume(.space, rimeContext: engine) == .space)
                        #expect(engine.processKey(XK_space))
                    } else if first == "1" {
                        #expect(engine.processKey(XK_Return))
                    } else {
                        engine.selectCandidate(at: 0)
                    }
                    let commit = try #require(engine.pollCommit())
                    #expect(commit == expected)
                    MarkedTextWriter.commit(commit, replacingMarkedText: true, to: proxy)
                    #expect(proxy.textView.text == expected)
                    #expect(proxy.insertions == [expected])
                    #expect(proxy.textView.markedTextRange == nil)
                    #expect(engine.preedit.isEmpty)
                    #expect(!engine.isLiteralComposition)
                    #expect(engine.pollCommit() == nil)
                }
            }
        }
        let automaticEnglish = KeyboardViewModel()
        _ = automaticEnglish.consume(.toggleLanguage)
        #expect(automaticEnglish.consume(.character("a"), rimeContext: engine) == .character("A"))
        let lockedModel = KeyboardViewModel()
        _ = lockedModel.consume(.shift)
        _ = lockedModel.consume(.shift)
        #expect(lockedModel.consume(.character("a"), rimeContext: engine) == .composingInput("A"))
        #expect(engine.appendLiteralInput("A"))
        #expect(engine.commitComposition())
        #expect(engine.pollCommit() == "A")
        #expect(lockedModel.consume(.character("b"), rimeContext: engine) == .composingInput("B"))
        #expect(engine.appendLiteralInput("B"))
        engine.reset()
        #expect(engine.processKey(65))
        #expect(engine.appendLiteralInput("！"))
        #expect(engine.preedit == "A！")
        engine.reset()
        #expect(engine.appendLiteralInput("A"))
        #expect(engine.processKey(XK_BackSpace))
        #expect(engine.preedit.isEmpty)
        #expect(!engine.isLiteralComposition)
        #expect(engine.appendLiteralInput("B"))
        engine.reset()
        #expect(!engine.isLiteralComposition)
        #expect(engine.preedit.isEmpty)
        #expect(engine.pollCommit() == nil)
    }
}
