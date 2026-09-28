import Foundation
import Observation
import Models

/// 输入框宿主状态（由键盘控制器维护，RIME 引擎不感知）：
/// 用于回车键蓝色高亮（`hasInputText`）、同步 toast（`toast`）与面板模式（`panelMode`）。
/// 引擎状态（`RimeContext`）只关心 RIME 自身（candidates/preedit/commit），
/// 不再承载宿主导航状态，职责分域。
@MainActor
@Observable
public final class InputState {
    /// 宿主输入框是否有文本（由键盘控制器维护，供回车键蓝色高亮使用）。
    public var hasInputText: Bool = false
    /// 同步瞬时提示（同步页按钮触发），KeyboardView 顶部悬浮胶囊据此展示；
    /// 收起的时长由键盘控制器掌握（`InputController.scheduleToastDismissal`）。
    public var toast: SyncToast? = nil
    /// 当前键盘面板：正常输入 / 同步设置页 / 日志页。候选为空时菜单按钮进入；
    /// 候选出现时控制器强制切回 `.input`（面板不挡候选）。
    public var panelMode: KeyboardPanelMode = .input

    public init() {}
}
