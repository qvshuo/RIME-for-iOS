import UIKit

@MainActor
public enum KeyboardFeedback {
    private static let feedback = UIImpactFeedbackGenerator(style: .rigid)

    public static func prepare() {
        feedback.prepare()
    }

    public static func play() {
        feedback.impactOccurred(intensity: 0.75)
        feedback.prepare()
    }
}
