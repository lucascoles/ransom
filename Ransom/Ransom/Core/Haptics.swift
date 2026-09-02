import UIKit

/// Thin wrapper so haptics read as intent ("a rep landed") rather than as UIKit noise.
enum Haptics {
    static func rep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A short celebratory run of taps for finishing a set.
    static func celebrate() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        for (index, delay) in [0.0, 0.09, 0.19, 0.32].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                generator.impactOccurred(intensity: 0.6 + Double(index) * 0.12)
            }
        }
    }
}
