import Foundation
import Observation
import KeyboardModels

@MainActor
@Observable
public final class InputState {
    public var hasInputText = false
    public var logExportHeight: CGFloat?
    public var panelMode: KeyboardPanelMode = .input
    public let sync = KeyboardSyncState.shared
    public var isSyncing: Bool { sync.isSyncing }
    public var toast: SyncToast? { sync.toast }

    public init() {}
}
