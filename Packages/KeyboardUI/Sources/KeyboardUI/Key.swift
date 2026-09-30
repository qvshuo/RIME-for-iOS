import SwiftUI
import Models

/// 纯色键帽，按压时切换填充色；字符键显示预览气泡。
public struct Key: View {
    let descriptor: KeyDescriptor
    let theme: Theme
    let shiftState: ShiftState
    let action: (KeyAction) -> Void
    /// 仅空格键长按同步用：把预告进度写入宿主状态（顶部胶囊读取展示）。
    var inputState: InputState?

    @State private var isPressed = false
    @State private var repeater: KeyPressRepeater?
    /// 空格键长按同步：步进计时器与已按住秒数（满 `Theme.spaceSyncHoldDuration` 秒触发）。
    @State private var spaceHoldTimer: Timer?
    @State private var holdElapsed: Double = 0
    @State private var spaceHoldTriggeredSync = false

    private var isRepeatable: Bool {
        descriptor.action.isBackspace
    }

    private var isSpaceAction: Bool {
        descriptor.action.isSpace
    }

    /// 仅字符键显示按压气泡；数字和符号布局在解析时同样使用 `.character`。
    private var previewText: String? {
        guard case .character = descriptor.action else { return nil }
        return descriptor.label
    }

    public init(
        descriptor: KeyDescriptor,
        theme: Theme,
        shiftState: ShiftState = .lowercase,
        inputState: InputState? = nil,
        action: @escaping (KeyAction) -> Void
    ) {
        self.descriptor = descriptor
        self.theme = theme
        self.shiftState = shiftState
        self.inputState = inputState
        self.action = action
    }

    public var body: some View {
        Group {
            if isRepeatable {
                repeatableKeyBody
            } else if isSpaceAction {
                spaceKeyBody
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

    /// 退格支持长按连打（0.5s 后每 0.1s 重复）。用 UIKit 触摸回调驱动起停：
    /// SwiftUI DragGesture 在键盘扩展里松手不可靠，系统手势中断时不走 onEnded。
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

    /// 空格键：单击上屏空格（双击=句号逻辑由控制器处理），长按 3 秒触发手动同步，
    /// 按住期间键面中央显示环形进度。不重复连打空格；长按期间松手则按普通空格
    /// 处理，满 3 秒才触发同步并吞掉本次松手。
    private var spaceKeyBody: some View {
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
                        startSpaceHoldTimer()
                    },
                    onRelease: {
                        isPressed = false
                        cancelSpaceHoldTimer()
                        // 长按满 3 秒已触发同步，本次松手不再输入空格。
                        if !spaceHoldTriggeredSync {
                            action(.space)
                        }
                    },
                    onCancel: {
                        // 系统取消触摸 / 滑离：不插入空格，只复位视觉与长按计时。
                        isPressed = false
                        spaceHoldTriggeredSync = false
                        cancelSpaceHoldTimer()
                    }
                )
            }
            .onDisappear {
                cancelSpaceHoldTimer()
            }
    }

    /// 空格长按计时：每 0.05s 步进，超过 `Theme.spaceSyncPreviewDelay` 后把进度
    /// 写入 `InputState.syncHoldProgress`（顶部预告胶囊展示），满
    /// `Theme.spaceSyncHoldDuration` 秒触发同步（触觉 + `.startSync`）。
    private func startSpaceHoldTimer() {
        spaceHoldTriggeredSync = false
        holdElapsed = 0
        inputState?.syncHoldProgress = nil
        spaceHoldTimer?.invalidate()
        // self 是结构体值拷贝，闭包内通过 @State 的非 mutating setter 写共享存储即可。
        let timer = Timer(timeInterval: 0.05, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                guard holdElapsed < Theme.spaceSyncHoldDuration else { return }
                holdElapsed = min(Theme.spaceSyncHoldDuration, holdElapsed + 0.05)
                if holdElapsed >= Theme.spaceSyncPreviewDelay {
                    inputState?.syncHoldProgress =
                        holdElapsed / Theme.spaceSyncHoldDuration
                }
                if holdElapsed >= Theme.spaceSyncHoldDuration {
                    spaceHoldTimer?.invalidate()
                    spaceHoldTimer = nil
                    inputState?.syncHoldProgress = nil
                    spaceHoldTriggeredSync = true
                    KeyboardFeedback.play()
                    action(.startSync)
                }
            }
        }
        spaceHoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelSpaceHoldTimer() {
        spaceHoldTimer?.invalidate()
        spaceHoldTimer = nil
        holdElapsed = 0
        inputState?.syncHoldProgress = nil
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

    /// shift 处于激活（一次大写或大写锁定）时显示实心上箭头，与原生输入法一致。
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
