import Foundation
import KeyboardModels

public struct KeyDescriptor: Sendable {
    public let label: String
    public let action: KeyAction
    public let style: KeyStyle
    public let width: CGFloat
    /// JSON 的 fixed 为点宽；nil 表示参与弹性分摊。
    public let fixedWidth: CGFloat?

    public init(
        label: String,
        action: KeyAction,
        style: KeyStyle,
        width: CGFloat,
        fixedWidth: CGFloat? = nil
    ) {
        self.label = label
        self.action = action
        self.style = style
        self.width = width
        self.fixedWidth = fixedWidth
    }

    public func with(label: String? = nil, style: KeyStyle? = nil) -> KeyDescriptor {
        KeyDescriptor(
            label: label ?? self.label,
            action: action,
            style: style ?? self.style,
            width: width,
            fixedWidth: fixedWidth
        )
    }
}

public enum KeyStyle: String, Sendable {
    case normal
    case special
    case confirm
}

public struct RowDescriptor: Sendable {
    public let keys: [KeyDescriptor]
    public let leadingPadding: CGFloat

    public init(keys: [KeyDescriptor], leadingPadding: CGFloat = 0) {
        self.keys = keys
        self.leadingPadding = leadingPadding
    }
}

public struct LayoutDescriptor: Sendable {
    public let rows: [RowDescriptor]

    public init(rows: [RowDescriptor]) {
        self.rows = rows
    }
}
