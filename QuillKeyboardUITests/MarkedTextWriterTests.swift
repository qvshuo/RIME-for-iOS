import UIKit
import Testing
@testable import KeyboardUI

@MainActor
final class TextViewProxy: NSObject, UITextDocumentProxy {
    let textView = UITextView()
    let documentIdentifier = UUID()
    var keepsCursorAtMarkedStart = false
    private(set) var insertions: [String] = []

    var documentInputMode: UITextInputMode? { textView.textInputMode }
    var hasText: Bool { textView.hasText }
    var documentContextBeforeInput: String? {
        (textView.text as NSString).substring(to: textView.selectedRange.location)
    }
    var documentContextAfterInput: String? {
        (textView.text as NSString).substring(from: NSMaxRange(textView.selectedRange))
    }
    var selectedText: String? {
        (textView.text as NSString).substring(with: textView.selectedRange)
    }
    func insertText(_ text: String) { insertions.append(text); textView.insertText(text) }
    func deleteBackward() { textView.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        textView.selectedRange = NSRange(location: textView.selectedRange.location + offset, length: 0)
    }
    func setMarkedText(_ text: String, selectedRange: NSRange) {
        textView.setMarkedText(text, selectedRange: selectedRange)
    }
    func unmarkText() {
        let start = textView.markedTextRange.map { textView.offset(from: textView.beginningOfDocument, to: $0.start) }
        textView.unmarkText()
        if keepsCursorAtMarkedStart, let start { textView.selectedRange = NSRange(location: start, length: 0) }
    }
}

@MainActor
struct MarkedTextWriterTests {
    @Test("提交组合和后续字符时保留周围文本与正确光标", arguments: [false, true])
    func replaceMarkedText(keepsCursorAtStart: Bool) {
        for text in ["A1", "A！", "ABC123", "你好。"] {
            let proxy = TextViewProxy()
            proxy.keepsCursorAtMarkedStart = keepsCursorAtStart
            proxy.textView.text = "前🙂后"
            proxy.textView.selectedRange = NSRange(location: 3, length: 0)
            proxy.setMarkedText("ABC", selectedRange: NSRange(location: 3, length: 0))
            MarkedTextWriter.commit(text, replacingMarkedText: true, to: proxy)
            #expect(proxy.textView.text == "前🙂" + text + "后")
            #expect(proxy.textView.markedTextRange == nil)
            #expect(proxy.textView.selectedRange == NSRange(location: 3 + text.utf16.count, length: 0))
            #expect(proxy.insertions == [text])
        }
    }
}
