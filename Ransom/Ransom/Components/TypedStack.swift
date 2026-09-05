import SwiftUI

/// One line in a typed block, with its own styling.
struct TypedLine: Identifiable {
    let id = UUID()
    var text: String
    var font: Font
    var colour: Color
    /// Extra pause before this line starts, for a beat between thoughts.
    var leadIn: Double = 0
    /// Shrink to stay on one line rather than wrap. For the big figures, where a
    /// wrap splits the number from its unit and halves the impact.
    var fitsOneLine: Bool = false

    static func line(_ text: String, _ font: Font, _ colour: Color,
                     leadIn: Double = 0, fitsOneLine: Bool = false) -> TypedLine {
        TypedLine(text: text, font: font, colour: colour,
                  leadIn: leadIn, fitsOneLine: fitsOneLine)
    }
}

/// Types a block of lines on, one character at a time, in order.
///
/// Copy delivered as a finished block is read in a glance and absorbed by nobody.
/// Typing sets the pace: the reader arrives at the last line at the moment it
/// lands rather than several seconds before it. Used for the cold open and the
/// projection, which are the two screens whose whole job is to be felt.
///
/// Each line gets its own progress value animated in sequence. A single shared
/// value looked right and typed every line at once - each renderer interpolates
/// its own copy over the same window, so deriving "where is this line up to"
/// from one number loses the ordering entirely.
struct TypedStack: View {
    var lines: [TypedLine]
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 6
    /// Unhurried on purpose. Fast typing is just a stutter before the text
    /// appears; at this pace the reader is reading along with it.
    var perCharacter: Double = 0.055
    /// Skip straight to the finished text - Reduce Motion, or an impatient tap.
    var isInstant: Bool = false
    var onComplete: () -> Void = {}

    @State private var progress: [Double] = []

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                typed(line.text, progress: value(at: index))
                    .font(line.font)
                    .foregroundStyle(line.colour)
                    .lineLimit(line.fitsOneLine ? 1 : nil)
                    .minimumScaleFactor(line.fitsOneLine ? 0.5 : 1)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .task(id: lines.map(\.text).joined()) {
            progress = Array(repeating: 0, count: lines.count)
            guard !isInstant else {
                progress = Array(repeating: 1, count: lines.count)
                onComplete()
                return
            }

            for (index, line) in lines.enumerated() {
                if line.leadIn > 0 {
                    try? await Task.sleep(for: .seconds(line.leadIn))
                    if Task.isCancelled { return }
                }
                let duration = Double(line.text.count) * perCharacter
                // Linear, because the per-glyph spring supplies the character;
                // easing the reveal as well makes the line arrive in a rush.
                withAnimation(.linear(duration: duration)) { set(index, to: 1) }
                try? await Task.sleep(for: .seconds(duration))
                if Task.isCancelled { return }
            }
            onComplete()
        }
        .onChange(of: isInstant) { _, instant in
            guard instant else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                progress = Array(repeating: 1, count: lines.count)
            }
        }
    }

    private func value(at index: Int) -> Double {
        index < progress.count ? progress[index] : 0
    }

    private func set(_ index: Int, to newValue: Double) {
        guard index < progress.count else { return }
        progress[index] = newValue
    }

    /// One line's glyphs, keeping native text layout so wrapping, kerning and
    /// alignment stay the system's job rather than ours.
    @ViewBuilder
    private func typed(_ text: String, progress: Double) -> some View {
        if #available(iOS 18.0, *) {
            Text(text).textRenderer(TypeOnRenderer(progress: progress))
        } else {
            // Pre-18 has no per-glyph hook, so it falls back to a clean prefix
            // reveal. Same pacing, no bounce.
            Text(String(text.prefix(Int((progress * Double(text.count)).rounded()))))
        }
    }
}

/// Draws each glyph in as the reveal passes over it, with a small overshoot.
///
/// A prefix reveal pops whole characters into existence, which reads as
/// mechanical however fast it runs. Animating per glyph - fading up, drifting
/// down a couple of points and settling from slightly too large - is what makes
/// it feel handwritten rather than printed.
@available(iOS 18.0, *)
struct TypeOnRenderer: TextRenderer, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// How much of the line one glyph's entrance occupies. Wide enough that
    /// several are always in flight, so the motion reads as a wave rather than
    /// as one letter at a time.
    private let window = 0.12

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        guard !glyphs.isEmpty else { return }

        let count = Double(glyphs.count)
        for (index, glyph) in glyphs.enumerated() {
            // Starts are packed into 0...(1 - window) so the final glyph begins
            // its entrance with a full window left to finish it. Spreading them
            // across the whole 0...1 left the last few characters frozen part-way
            // through their fade, which reads as permanently blurred.
            let start = (Double(index) / count) * (1 - window)
            let t = min(1, max(0, (progress - start) / window))
            guard t > 0 else { continue }

            // Overshoot then settle: back-ease out, the shape a spring gives,
            // without the cost of one animator per character.
            let eased = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2)
            let scale = 1 + 0.22 * (1 - eased)
            let rect = glyph.typographicBounds.rect

            var copy = context
            copy.opacity = t
            copy.translateBy(x: rect.midX, y: rect.midY)
            copy.scaleBy(x: scale, y: scale)
            copy.translateBy(x: -rect.midX, y: -rect.midY + (1 - eased) * -3)
            copy.draw(glyph)
        }
    }
}
