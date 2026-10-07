import Foundation
import Observation
import KeyboardModels

@MainActor
@Observable
public final class InputState {
    public var isVisible = true
    public var hasInputText = false
    public var panelMode: KeyboardPanelMode = .input
    public let sync = KeyboardSyncState.shared
    public var isSyncing: Bool { sync.isSyncing }

    public init() {}
}
