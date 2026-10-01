import Foundation
import SwiftUI
import UIKit
import Testing
import RimeEngine
import Models
@testable import KeyboardUI

@MainActor
struct KeyboardPanelRenderingTests {
    @Test("功能页在深浅主题下按各自内容高度布局", arguments: [false, true])
    func renderPanels(dark: Bool) throws {
        for mode in [KeyboardPanelMode.input, .sync, .log] {
            let state = InputState()
            state.panelMode = mode
            let content = KeyboardView(rimeContext: .shared, inputState: state, onKey: { _ in })
                .preferredColorScheme(dark ? .dark : .light)
                .background(Color(uiColor: dark ? UIColor(white: 43.0 / 255, alpha: 1) : UIColor(white: 0.92, alpha: 1)))
            let height: CGFloat = mode == .sync ? 350 : 266
            let hosting = UIHostingController(rootView: content)
            let size = hosting.sizeThatFits(in: CGSize(width: 402, height: height))
            #expect(size == CGSize(width: 402, height: height))

        }
    }
}
