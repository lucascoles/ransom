import SwiftUI

/// Rex plus a speech bubble. This pairing is the app's voice — used on the home
/// screen, between onboarding steps, and after every set.
struct RexScene: View {
    var pose: RexPose = .idle
    var line: String
    var size: CGFloat = 150
    var bubbleAlignment: HorizontalAlignment = .leading
    /// Types the line out one character at a time the first time it appears.
    var typewriter: Bool = false
    /// Puts a soft contact shadow under him, for the one place he stands on
    /// something (Home's masthead) rather than floating on paper.
    var grounded: Bool = false

    @State private var revealed: Int = 0
    @Environment(\.colorScheme) private var scheme

    /// A contact shadow has to be darker than the ground it falls on, and the
    /// ground in dark mode is already nearly black: 15% black over it was
    /// nothing, so Rex floated. Deeper in the dark, unchanged on paper.
    private var contactShadow: Double { scheme == .dark ? 0.5 : 0.15 }

    /// How far above the bottom of his frame his feet actually are, as a fraction
    /// of `size`. Measured off the rendered artwork, not guessed.
    private var feetInset: CGFloat {
        RexImage.loopName(for: pose) != nil ? 0.205 : -0.007
    }

    private var shownLine: String {
        guard typewriter else { return line }
        return String(line.prefix(revealed))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if bubbleAlignment == .trailing { bubble }
            // A clip where one exists, the drawing everywhere else. Rex stops
            // being a picture of a character on the two screens you actually sit
            // and look at.
            Group {
                if let clip = RexImage.loopName(for: pose) {
                    RexClip(name: clip, size: size, fallback: pose)
                        .id(clip)
                } else {
                    RexImage(pose: pose, size: size)
                }
            }
            .background(alignment: .bottom) {
                if grounded {
                    // The clips and the stills sit differently in their frames — the
                    // loops leave about a fifth of the height empty below his feet,
                    // the PNGs only 3% — so the shadow follows whichever is actually
                    // on screen. Getting this wrong is very visible: too low and it
                    // reads as a smudge he floats above, too high and it disappears
                    // inside him.
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [.black.opacity(contactShadow), .black.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.34
                            )
                        )
                        .frame(width: size * 0.62, height: size * 0.10)
                        .offset(y: -size * feetInset)
                }
            }
            if bubbleAlignment == .leading { bubble }
        }
        .onAppear(perform: startTyping)
        .onChange(of: line) { _, _ in
            revealed = 0
            startTyping()
        }
    }

    private var bubble: some View {
        Text(shownLine)
            .font(RansomFont.body(15))
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                SpeechBubble(pointsLeft: bubbleAlignment == .leading)
                    .fill(Palette.surface)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            )
            .overlay(
                SpeechBubble(pointsLeft: bubbleAlignment == .leading)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.top, size * 0.12)
            .opacity(shownLine.isEmpty ? 0 : 1)
    }

    private func startTyping() {
        guard typewriter else {
            revealed = line.count
            return
        }
        let characters = Array(line)
        for index in characters.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.018) {
                guard line.count == characters.count else { return }
                revealed = index + 1
            }
        }
    }
}

/// A rounded bubble with a small tail pointing back at Rex.
struct SpeechBubble: Shape {
    var pointsLeft: Bool = true
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 9
        let body = CGRect(
            x: pointsLeft ? rect.minX + tail : rect.minX,
            y: rect.minY,
            width: rect.width - tail,
            height: rect.height
        )

        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)

        let anchorY = min(rect.minY + 26, rect.midY)
        var beak = Path()
        if pointsLeft {
            beak.move(to: CGPoint(x: body.minX + 2, y: anchorY - 9))
            beak.addLine(to: CGPoint(x: rect.minX, y: anchorY))
            beak.addLine(to: CGPoint(x: body.minX + 2, y: anchorY + 9))
        } else {
            beak.move(to: CGPoint(x: body.maxX - 2, y: anchorY - 9))
            beak.addLine(to: CGPoint(x: rect.maxX, y: anchorY))
            beak.addLine(to: CGPoint(x: body.maxX - 2, y: anchorY + 9))
        }
        beak.closeSubpath()
        path.addPath(beak)
        return path
    }
}

#Preview {
    VStack(spacing: 30) {
        RexScene(pose: .coach, line: "Twelve push-ups and Instagram is all yours.")
        RexScene(pose: .blocked, line: "Nice try. Rex saw that.", bubbleAlignment: .trailing)
    }
    .padding()
    .ransomScreenBackground()
}
