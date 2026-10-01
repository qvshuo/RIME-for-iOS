import SwiftUI
import KeyboardModels

public struct Key: View {
    let descriptor: KeyDescriptor
    let theme: Theme
    let shiftState: ShiftState
    let action: (KeyAction) -> Void

    @State private var isPressed = false
    @State private var repeater: KeyPressRepeater?

    private var isRepeatable: Bool {
        descriptor.action.isBackspace
    }

    private var previewText: String? {
        guard case .character = descriptor.action else { return nil }
        return descriptor.label
    }

    public init(
        descriptor: KeyDescriptor,
        theme: Theme,
        shiftState: ShiftState = .lowercase,
        action: @escaping (KeyAction) -> Void
    ) {
        self.descriptor = descriptor
        self.theme = theme
        self.shiftState = shiftState
        self.action = action
    }

    public var body: some View {
        Group {
            if isRepeatable {
                repeatableKeyBody
            } else {
                Button(action: { action(descriptor.action) }) {
                    keyLabel
                        .foregroundStyle(foregroundColor)
                }
                .buttonStyle(
                    KeyButtonStyle(
                        theme: theme,
                        style: descriptor.style,
                        previewText: previewText,
                        pressed: $isPressed
                    )
                )
            }
        }
        .zIndex(isPressed ? 1 : 0)
    }

    /// SwiftUI 手势中断可能不回调 onEnded，退格计时由 UIKit 触摸驱动。
    private var repeatableKeyBody: some View {
        keyLabel
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyBackground(
                isPressed: isPressed,
                style: descriptor.style,
                theme: theme
            )
            .contentShape(Rectangle())
            // 显式覆盖系统默认按键动效（约 0.2s，太慢有迟滞感）。
            .animation(.easeOut(duration: 0.05), value: isPressed)
            .overlay {
                KeyTouchTracker(
                    onPress: {
                        guard !isPressed else { return }
                        isPressed = true
                        KeyboardFeedback.play()
                        if repeater == nil {
                            repeater = KeyPressRepeater(
                                fire: { action(descriptor.action) },
                                feedback: { KeyboardFeedback.play() }
                            )
                        }
                        repeater?.startPress()
                    },
                    onRelease: {
                        isPressed = false
                        repeater?.endPress()
                    },
                    onCancel: {
                        // 触摸被系统取消或滑离按键：停止连打并复位视觉，不产生动作。
                        isPressed = false
                        repeater?.endPress()
                    }
                )
            }
            .onDisappear {
                repeater?.endPress()
            }
    }

    @ViewBuilder
    private var keyLabel: some View {
        switch descriptor.action {
        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: theme.iconFontSize, weight: .medium))
                .accessibilityLabel("删除")
        case .space:
            Color.clear
                .accessibilityLabel("空格")
        case .return:
            Text(descriptor.label)
                .font(.system(size: theme.specialKeyFontSize, weight: .regular))
                .accessibilityLabel(descriptor.label == "⏎" ? "换行" : descriptor.label)
        case .numbers, .letters, .symbols:
            Text(descriptor.label)
                .font(.system(size: theme.specialKeyFontSize, weight: .regular))
                .accessibilityLabel(descriptor.label)
        case .toggleLanguage:
            Text(descriptor.label)
                .font(.system(size: theme.specialKeyFontSize, weight: .regular))
                .accessibilityHint("切换中英文输入")
        case .shift:
            Image(systemName: shiftImageName)
                .font(.system(size: theme.iconFontSize, weight: shiftState == .uppercaseLocked ? .semibold : .medium))
                .scaleEffect(shiftState == .uppercaseLocked ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.1), value: shiftState)
                .accessibilityLabel(shiftState == .lowercase ? "大写" : "小写")
        default:
            Text(descriptor.label)
                .font(theme.font)
                .accessibilityLabel(descriptor.label)
        }
    }

    private var shiftImageName: String {
        switch shiftState {
        case .uppercaseOnce, .uppercaseLocked:
            return "shift.fill"
        case .lowercase:
            return "shift"
        }
    }

    private var foregroundColor: Color {
        switch descriptor.style {
        case .confirm:
            // 按压时底色变统一按压色，前景同步换 keyForeground 避免亮底亮字。
            return isPressed ? theme.keyForeground : .white
        case .special:
            return theme.specialKeyForeground
        default:
            return theme.keyForeground
        }
    }
}

private struct KeyButtonStyle: ButtonStyle {
    let theme: Theme
    let style: KeyStyle
    let previewText: String?
    let pressed: Binding<Bool>

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyBackground(
                isPressed: configuration.isPressed,
                style: style,
                theme: theme
            )
            .contentShape(Rectangle())
            // 显式覆盖系统默认按键动效（约 0.2s，太慢有迟滞感）。
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            .overlay(alignment: .top) {
                if configuration.isPressed, let previewText {
                    Text(previewText)
                        .font(.system(size: theme.previewFontSize, weight: .regular))
                        .foregroundStyle(theme.keyForeground)
                        .frame(width: theme.previewBubbleSide, height: theme.previewBubbleSide)
                        .background(
                            RoundedRectangle(cornerRadius: theme.previewBubbleCornerRadius, style: .continuous)
                                // 不透明：半透明气泡会透出键缝显得「透明」。
                                .fill(theme.previewBubbleBackground)
                        )
                        .floatingShadow()
                        .offset(y: theme.previewBubbleOffsetY)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressed.wrappedValue = isPressed
                if isPressed {
                    KeyboardFeedback.play()
                }
            }
    }
}
