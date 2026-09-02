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

    @State private var revealed: Int = 0

    private var shownLine: String {
        guard typewriter else { return line }
        return String(line.prefix(revealed))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if bubbleAlignment == .trailing { bubble }
            RexImage(pose: pose, size: size)
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
            .font(ReppFont.body(15))
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
    .reppScreenBackground()
}
