import SwiftUI

/// Rex poses that only the intake uses, drawn straight from the asset catalog.
///
/// `RexPose` and `RexImage` belong to the mascot layer, and adding cases there
/// ripples into the shield, the home screen and the set screen. These two poses
/// are greeting-card moments that exist only in the funnel, so they are kept out
/// of the shared vocabulary until something outside the intake wants them. The
/// assets sit on the same 451×640 canvas as every other pose, feet on the same
/// baseline, so they cross-fade cleanly with `RexImage` where the two meet.
enum IntakeRexPose {
    case wave
    case thumbsUp

    var assetName: String {
        switch self {
        case .wave:     return "RexWave"
        case .thumbsUp: return "RexThumbsUp"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .wave:     return "Rex, waving hello"
        case .thumbsUp: return "Rex, giving a thumbs up"
        }
    }
}

struct IntakeRexImage: View {
    var pose: IntakeRexPose
    var size: CGFloat = 150

    @State private var breathing = false

    /// Matches `RexImage` exactly, so a wave beside an idle is the same height.
    private static let aspect: CGFloat = 640.0 / 451.0

    var body: some View {
        Image(pose.assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size * Self.aspect)
            .scaleEffect(x: breathing ? 1.012 : 1, y: breathing ? 0.988 : 1, anchor: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityLabel(pose.accessibilityLabel)
    }
}

/// `RexScene` for the intake-only poses: same bubble, same layout, so the
/// conversation doesn't change shape when Rex changes expression.
struct IntakeRexScene: View {
    var pose: IntakeRexPose
    var line: String
    var size: CGFloat = 150

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            IntakeRexImage(pose: pose, size: size)

            Text(line)
                .font(RansomFont.body(15))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    SpeechBubble(pointsLeft: true)
                        .fill(Palette.surface)
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
                )
                .overlay(
                    SpeechBubble(pointsLeft: true)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
                .frame(maxWidth: 220, alignment: .leading)
                .padding(.top, size * 0.12)
        }
    }
}
