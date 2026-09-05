import SwiftUI

/// The moment the app opens: Rex drops in, lands, and the name arrives under him.
///
/// On the paper canvas rather than a full-bleed brand field. A dark or tangerine
/// title card is louder, but it also arrives as a hard cut against every screen
/// that follows — and Rex, being made of the brand colour himself, needs the pale
/// ground to read the way he does everywhere else in the app.
///
/// iOS launch screens are storyboards and cannot animate, so the real launch
/// screen stays a still and this plays on top of the app the instant our own code
/// is running. It is drawn rather than filmed — a few hundred bytes of animation
/// instead of a megabyte of video, sharp at any size, and tunable to the frame.
///
/// Long enough to actually be seen and no longer. This app is often opened by
/// someone who has just been stopped from opening Instagram and wants their reps,
/// so the flourish runs a little over a second and a half and any tap skips
/// straight past it.
struct LaunchSplash: View {
    var onFinish: () -> Void

    @State private var hasLanded = false
    @State private var showsName = false
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    if hasLanded && !reduceMotion {
                        SparkleBurst()
                    }

                    RexImage(pose: .cheer, size: 170)
                        .offset(y: hasLanded ? 0 : -220)
                        .opacity(hasLanded ? 1 : 0)
                }
                .frame(height: 190)

                Text("Ransom")
                    .font(RansomFont.display(44))
                    .foregroundStyle(Palette.ink)
                    .opacity(showsName ? 1 : 0)
                    .offset(y: showsName ? 0 : 12)
                    .frame(height: 54, alignment: .top)
            }
            .padding(.bottom, 40)
        }
        .opacity(isLeaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .onAppear(perform: run)
    }

    private func run() {
        guard !reduceMotion else {
            hasLanded = true; showsName = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: finish)
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
            hasLanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            Haptics.tap()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { showsName = true }
        }
        // Held here rather than cut short: the drop and the wordmark are done by
        // roughly half a second, and the rest is simply letting it be looked at.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65, execute: finish)
    }

    /// Idempotent: the timer and an impatient tap both land here, and whichever
    /// arrives second must not fire a second dismissal mid-fade.
    private func finish() {
        guard !isLeaving else { return }
        withAnimation(.easeOut(duration: 0.26)) { isLeaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: onFinish)
    }
}

/// Four-pointed sparkles that pop outward as Rex lands.
private struct SparkleBurst: View {
    @State private var isOut = false

    private let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (-78, -46, 20, 0.00), (72, -58, 26, 0.05), (-92, 34, 15, 0.10),
        (88, 22, 18, 0.03), (-40, -82, 14, 0.08), (46, 74, 16, 0.12),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(sparkles.enumerated()), id: \.offset) { _, s in
                Sparkle()
                    .fill(Palette.brand.opacity(0.55))
                    .frame(width: s.size, height: s.size)
                    .scaleEffect(isOut ? 1 : 0.2)
                    .opacity(isOut ? 0 : 1)
                    .offset(x: s.x * (isOut ? 1 : 0.55), y: s.y * (isOut ? 1 : 0.55))
                    .animation(.easeOut(duration: 0.55).delay(s.delay), value: isOut)
            }
        }
        .onAppear { isOut = true }
        .allowsHitTesting(false)
    }
}

/// A four-pointed star with concave sides — the shape reads as a sparkle rather
/// than a plus sign because the waist is pulled almost to the centre.
private struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let waist = r * 0.22

        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y),
                          control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),
                          control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y),
                          control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r),
                          control: CGPoint(x: c.x - waist, y: c.y - waist))
        path.closeSubpath()
        return path
    }
}
