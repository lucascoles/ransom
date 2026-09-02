import SwiftUI

/// Rex, as artwork.
///
/// Every pose in `RexPose` now has its own illustration, all drawn from the same
/// character reference and registered on a shared canvas — same scale, feet on the
/// same baseline — so moving between them is a clean cross-fade rather than a jump.
///
/// The push-up is the exception worth knowing about: rather than snapping between
/// two frames, it cross-fades top into bottom on `depth`, so the character tracks
/// the sensor reading continuously instead of popping at the halfway mark.
struct RexImage: View {
    var pose: RexPose = .idle
    var size: CGFloat = 150
    /// Idle breathing. Turn off in lists, or where the character is decorative.
    var isAlive: Bool = true
    /// 0 = top of the rep, 1 = bottom. Only read for `.pushUp`.
    var depth: Double = 0

    @State private var breathing = false

    /// Every asset shares this canvas, which is what keeps the poses registered.
    private static let aspect: CGFloat = 640.0 / 451.0

    var body: some View {
        Group {
            if case .pushUp = pose {
                // Both frames occupy the same canvas, so stacking and cross-fading
                // them lands Rex exactly where the sensor says he is.
                ZStack {
                    art("RexPushUpTop").opacity(1 - clampedDepth)
                    art("RexPushUpBottom").opacity(clampedDepth)
                }
            } else {
                art(assetName(for: pose))
                    .id(pose)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size * Self.aspect)
        .scaleEffect(
            x: breathing && isAlive ? 1.012 : 1,
            y: breathing && isAlive ? 0.988 : 1,
            anchor: .bottom
        )
        .animation(.easeInOut(duration: 0.28), value: pose)
        .animation(.easeOut(duration: 0.12), value: depth)
        .onAppear {
            guard isAlive else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private func art(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    private var clampedDepth: Double { min(max(depth, 0), 1) }

    private func assetName(for pose: RexPose) -> String {
        switch pose {
        case .idle:    return "RexIdle"
        case .coach:   return "RexCoach"
        case .cheer:   return "RexCheer"
        case .blocked: return "RexBlocked"
        case .flex:    return "RexFlex"
        case .sad:     return "RexSad"
        // No artwork for sleep yet, and nothing in the app asks for it.
        case .sleep:   return "RexIdle"
        case .pushUp(let down): return down ? "RexPushUpBottom" : "RexPushUpTop"
        }
    }

    private var accessibilityDescription: String {
        switch pose {
        case .idle:    return "Rex, standing"
        case .coach:   return "Rex, explaining"
        case .cheer:   return "Rex, celebrating"
        case .blocked: return "Rex, blocking the way"
        case .flex:    return "Rex, flexing"
        case .sad:     return "Rex, disappointed"
        case .sleep:   return "Rex, asleep"
        case .pushUp:  return "Rex, doing a push-up"
        }
    }
}

#Preview("Every pose") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([RexPose.idle, .coach, .cheer, .blocked, .flex, .sad], id: \.self) { pose in
                RexImage(pose: pose, size: 120)
            }
            HStack {
                RexImage(pose: .pushUp(down: false), size: 150, depth: 0)
                RexImage(pose: .pushUp(down: true), size: 150, depth: 1)
            }
        }
        .padding()
    }
    .ransomScreenBackground()
}
