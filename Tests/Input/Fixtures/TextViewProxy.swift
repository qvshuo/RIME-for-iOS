import UIKit

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
