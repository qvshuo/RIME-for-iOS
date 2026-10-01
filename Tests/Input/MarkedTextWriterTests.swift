import UIKit
import Testing
@testable import KeyboardUI

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
