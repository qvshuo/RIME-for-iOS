import UIKit
import RimeEngine

@MainActor
public enum MarkedTextWriter {
    public static func finishComposition(appending suffix: String = "", from engine: RimeContext,
                                         replacingMarkedText: Bool, to proxy: any UITextDocumentProxy) {
        let preedit = engine.preedit
        let text = engine.commitComposition() ? engine.pollCommit() ?? preedit : preedit
        commit(text + suffix, replacingMarkedText: replacingMarkedText, to: proxy)
        engine.reset()
    }

    public static func commit(_ text: String, replacingMarkedText: Bool, to proxy: any UITextDocumentProxy) {
        if replacingMarkedText {
            // 部分宿主不保留 unmarkText 后的尾部光标；先移除组合，再一次性插入最终文本。
            proxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            proxy.unmarkText()
        }
        proxy.insertText(text)
    }
}
