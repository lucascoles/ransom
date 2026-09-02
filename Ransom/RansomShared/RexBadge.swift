import UIKit

/// Rex's face, drawn with Core Graphics.
///
/// The shield extension can't host SwiftUI, and shipping a bitmap would mean the
/// mascot lived in two places. Drawing him here keeps one definition of the
/// character and renders crisp at whatever size the shield asks for.
public enum RexBadge {
    public static func image(size: CGFloat = 160) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)

        let skin = UIColor(red: 0.42, green: 0.82, blue: 0.35, alpha: 1)
        let skinDark = UIColor(red: 0.12, green: 0.48, blue: 0.20, alpha: 1)
        let crest = UIColor(red: 0.78, green: 0.95, blue: 0.31, alpha: 1)
        let ink = UIColor(red: 0.08, green: 0.13, blue: 0.06, alpha: 1)

        return renderer.image { _ in
            let unit = size / 100

            // Crest spikes
            crest.setFill()
            skinDark.setStroke()
            for (index, x) in [30.0, 50.0, 70.0].enumerated() {
                let height = index == 1 ? 16.0 : 12.0
                let spike = UIBezierPath()
                spike.move(to: CGPoint(x: x * unit, y: (14 - height) * unit))
                spike.addLine(to: CGPoint(x: (x + 8) * unit, y: 20 * unit))
                spike.addLine(to: CGPoint(x: (x - 8) * unit, y: 20 * unit))
                spike.close()
                spike.lineWidth = 2 * unit
                spike.fill()
                spike.stroke()
            }

            // Head
            let head = UIBezierPath(ovalIn: CGRect(
                x: 8 * unit, y: 14 * unit, width: 84 * unit, height: 76 * unit
            ))
            skin.setFill()
            head.fill()
            skinDark.setStroke()
            head.lineWidth = 3 * unit
            head.stroke()

            // Snout highlight
            UIColor(red: 0.91, green: 0.98, blue: 0.75, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(
                x: 28 * unit, y: 56 * unit, width: 44 * unit, height: 30 * unit
            )).fill()

            // Eyes
            for x in [33.0, 67.0] {
                UIColor.white.setFill()
                let white = UIBezierPath(ovalIn: CGRect(
                    x: (x - 12) * unit, y: 30 * unit, width: 24 * unit, height: 26 * unit
                ))
                white.fill()
                skinDark.setStroke()
                white.lineWidth = 2 * unit
                white.stroke()

                ink.setFill()
                UIBezierPath(ovalIn: CGRect(
                    x: (x - 5) * unit, y: 38 * unit, width: 10 * unit, height: 10 * unit
                )).fill()

                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(
                    x: (x - 1) * unit, y: 39 * unit, width: 4 * unit, height: 4 * unit
                )).fill()
            }

            // Brows — Rex is unimpressed, not angry.
            skinDark.setStroke()
            for (x, direction) in [(33.0, -1.0), (67.0, 1.0)] {
                let brow = UIBezierPath()
                brow.move(to: CGPoint(x: (x - 11 * direction) * unit, y: 26 * unit))
                brow.addLine(to: CGPoint(x: (x + 9 * direction) * unit, y: 23 * unit))
                brow.lineWidth = 3.5 * unit
                brow.lineCapStyle = .round
                brow.stroke()
            }

            // Flat mouth
            ink.setStroke()
            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: 38 * unit, y: 71 * unit))
            mouth.addQuadCurve(
                to: CGPoint(x: 62 * unit, y: 71 * unit),
                controlPoint: CGPoint(x: 50 * unit, y: 68 * unit)
            )
            mouth.lineWidth = 3 * unit
            mouth.lineCapStyle = .round
            mouth.stroke()
        }
    }
}
