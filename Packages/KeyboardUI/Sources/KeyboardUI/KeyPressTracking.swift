import Foundation
import SwiftUI
import UIKit

final class KeyPressRepeater: @unchecked Sendable {
    private var timer: Timer?
    private var workItem: DispatchWorkItem?
    private let fire: () -> Void
    /// 首次按下的震动由触摸回调负责，此回调只用于重复触发。
    private let feedback: (() -> Void)?

    init(
        fire: @escaping () -> Void,
        feedback: (() -> Void)? = nil
    ) {
        self.fire = fire
        self.feedback = feedback
    }

    func startPress() {
        fire()
        // 防御：清掉上一次 press 残留的定时器，避免异常调用序列下双重触发。
        endPress()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.fire()
                self.feedback?()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func endPress() {
        workItem?.cancel()
        workItem = nil
        timer?.invalidate()
        timer = nil
    }
}

/// 只跟踪首个触摸；取消或滑离时停止重复，不产生松手动作。
struct KeyTouchTracker: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void
    let onCancel: (() -> Void)?

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
    }

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onPress = onPress
        view.onRelease = onRelease
        view.onCancel = onCancel
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        uiView.onPress = onPress
        uiView.onRelease = onRelease
        uiView.onCancel = onCancel
    }

    final class TrackerView: UIView {
        var onPress: (() -> Void)?
        var onRelease: (() -> Void)?
        var onCancel: (() -> Void)?

        private var activeTouch: UITouch?
        private var hasDrifted = false

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            bounds.contains(point) ? self : nil
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            guard activeTouch == nil, let touch = touches.first else { return }
            activeTouch = touch
            hasDrifted = false
            onPress?()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            guard let touch = activeTouch, touches.contains(touch), !hasDrifted else { return }
            // 滑出按键周边容差即视为漂移：停止长按计时、复位视觉，松手不再触发动作
            // （原生键盘的纠错手势）。
            let tolerance: CGFloat = 20
            let location = touch.location(in: self)
            if !bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(location) {
                hasDrifted = true
                onCancel?()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            if hasDrifted {
                onCancel?()
            } else {
                onRelease?()
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            guard activeTouch != nil else { return }
            activeTouch = nil
            onCancel?()
        }
    }
}
