import Foundation

/// 键盘面板模式：正常输入，或切换到同步 / 日志功能页。
/// 候选为空时菜单按钮出现在候选栏左侧，点击进入对应面板。
public enum KeyboardPanelMode: Sendable, Equatable {
    case input
    case sync
    case log
}
