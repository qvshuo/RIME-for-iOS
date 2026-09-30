import Foundation
import SwiftUI
import Testing
import RimeEngine
import Models
@testable import KeyboardUI

@MainActor
struct KeyboardPanelRenderingTests {
    @Test("功能页在深浅主题下保持键盘高度并可渲染", arguments: [false, true])
    func renderPanels(dark: Bool) throws {
        for (name, mode) in [("input", KeyboardPanelMode.input), ("sync", .sync), ("log", .log)] {
            let state = InputState()
            state.panelMode = mode
            let content = KeyboardView(rimeContext: .shared, inputState: state, onKey: { _ in })
                .preferredColorScheme(dark ? .dark : .light)
                .background(Color(uiColor: dark ? UIColor(white: 43.0 / 255, alpha: 1) : UIColor(white: 0.92, alpha: 1)))
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: 402, height: 266)
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            #expect(image.size == CGSize(width: 402, height: 266))
            let url = URL.temporaryDirectory.appendingPathComponent("Quill-preview-\(name)-\(dark ? "dark" : "light").png")
            try #require(image.pngData()).write(to: url)
            print("Quill preview: \(url.path)")
        }
    }
}
