import SwiftUI

/// Rex, as artwork.
///
/// He was previously drawn in vectors (`Rex.swift`), which bought smooth pose
/// interpolation at the cost of looking hand-drawn. He's now illustrated art, so
/// this view maps the same pose vocabulary onto image assets.
///
/// Only the hero pose exists today, so every pose resolves to it and the
/// difference between poses is carried by transform — a lean, a bounce, a squash.
/// When the rest of the sprite set lands, `assetName(for:)` is the only thing that
/// changes, and every call site keeps working.
struct RexImage: View {
    var pose: RexPose = .idle
    var size: CGFloat = 150
    /// Idle breathing. Turn off in lists, or where the character is decorative.
    var isAlive: Bool = true
    /// 0 = top of the rep, 1 = bottom. Drives the push-up squash while a set runs.
    var depth: Double = 0

    @State private var breathing = false

    /// The artwork is 451x640 at source; every asset in the set keeps that ratio.
    private let aspect: CGFloat = 640.0 / 451.0

    var body: some View {
        Image(assetName(for: pose))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size * aspect)
            .scaleEffect(
                x: transform.scaleX * (breathing && isAlive ? 1.012 : 1),
                y: transform.scaleY * (breathing && isAlive ? 0.988 : 1),
                anchor: .bottom
            )
            .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
            .offset(y: transform.offsetY)
            .animation(.spring(response: 0.42, dampingFraction: 0.62), value: pose)
            .animation(.easeOut(duration: 0.16), value: depth)
            .onAppear {
                guard isAlive else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }

    private func assetName(for pose: RexPose) -> String {
        // One asset for now. Named per pose so the swap is a data change, not a
        // code change, once the full set is generated.
        "RexHero"
    }

    /// What distinguishes the poses until there's real art for each of them.
    private var transform: (scaleX: CGFloat, scaleY: CGFloat, rotation: Double, offsetY: CGFloat) {
        switch pose {
        case .idle:
            return (1, 1, 0, 0)
        case .cheer:
            return (1.04, 1.06, 0, -6)
        case .coach:
            return (1, 1, -3, 0)
        case .flex:
            return (1.06, 1.03, 0, 0)
        case .blocked:
            return (1.03, 0.99, 0, 0)
        case .sad:
            return (0.97, 0.94, 0, 6)
        case .sleep:
            return (1, 0.96, -4, 4)
        case .pushUp:
            // Squash toward the floor as the rep bottoms out.
            let d = CGFloat(min(max(depth, 0), 1))
            return (1 + 0.06 * d, 1 - 0.14 * d, 0, 14 * d)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            RexImage(pose: .idle, size: 110)
            RexImage(pose: .cheer, size: 110)
            RexImage(pose: .coach, size: 110)
        }
        RexImage(pose: .pushUp(down: true), size: 150, depth: 1)
    }
    .padding()
    .reppScreenBackground()
}
