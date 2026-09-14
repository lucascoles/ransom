import AVFoundation
import SwiftUI

/// The moment after the paywall: Rex jumps, the confetti goes, and the person
/// who just paid is told the thing that makes it worth it.
///
/// It used to cut straight from a successful purchase to Home, so the biggest
/// decision of someone's first session passed with no acknowledgement at all.
/// This is shown *after* onboarding is saved, never instead of saving it: the
/// app can be killed on this screen and the user still lands on Home next time,
/// rather than being sent back through intake having already paid.
///
/// The words are built from the user's own plan, the same figure the plan screen
/// called "back in your hands, every day", turned into a year. Nothing here is a
/// number the user did not give us.
struct WelcomeCelebration: View {
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showWords = false
    @State private var showButton = false
    @State private var confetti = false

    /// Where Rex lands in `RexWelcomeJump.mov`, read off the clip's frames. The
    /// haptics are timed to his feet, which is what makes the jump feel physical
    /// rather than decorative.
    private static let firstLanding = 1.75
    private static let secondLanding = 3.6

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 20)

                Group {
                    if reduceMotion {
                        RexImage(pose: .cheer, size: 280)
                    } else {
                        OneShotAlphaClip(name: "RexWelcomeJump")
                            .frame(width: 370, height: 370)
                    }
                }

                VStack(spacing: 12) {
                    Text(Self.headline(firstName: model.profile.firstName))
                        .font(RansomFont.display(34))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    Text(Self.subline(minutesSavedPerDay: model.plan.projectedMinutesSavedPerDay))
                        .font(RansomFont.body(18))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .opacity(showWords ? 1 : 0)
                .offset(y: showWords ? 0 : 12)

                Spacer(minLength: 20)

                PrimaryButton(title: "Let's go", action: onDone)
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 12)
                    .opacity(showButton ? 1 : 0)
                    .disabled(!showButton)
            }

            ConfettiBurst(isActive: confetti)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            showWords = true
            showButton = true
            Haptics.success()
            return
        }
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.easeOut(duration: 0.5)) { showWords = true }
        try? await Task.sleep(for: .seconds(Self.firstLanding - 0.3))
        Haptics.tap()
        // The button arrives before the jump finishes. Watching the whole thing
        // is a pleasure, not a toll.
        withAnimation(.easeOut(duration: 0.4)) { showButton = true }
        try? await Task.sleep(for: .seconds(Self.secondLanding - Self.firstLanding))
        Haptics.celebrate()
        confetti = true
    }

    // MARK: - Words

    /// "Proud of you, Lucas." or, with no name, "Proud of you." A name made only
    /// of spaces is no name.
    static func headline(firstName: String) -> String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Proud of you." : "Proud of you, \(name)."
    }

    /// The daily saving from the plan, told as a year. Days when it is at least
    /// two, hours below that, and no number at all when there is no saving to
    /// speak of, rather than inventing one. Two lines, one idea each, so the
    /// call to action never wraps into an orphan.
    static func subline(minutesSavedPerDay minutes: Int) -> String {
        guard minutes > 0 else { return "Every set buys back your time.\nLet's go get it." }
        let hoursPerYear = minutes * 365 / 60
        let daysPerYear = hoursPerYear / 24
        if daysPerYear >= 2 {
            return "That's \(daysPerYear) days of your year coming back.\nLet's go get them."
        }
        return "That's \(hoursPerYear) hours of your year coming back.\nLet's go get them."
    }
}

/// Plays a bundled alpha clip once and holds its last frame.
///
/// The looping `PingPongClip` is the wrong tool here: a celebration that
/// restarts reads as a glitch, and this clip was generated to end on the pose it
/// began with, so holding the final frame leaves Rex cheering.
private struct OneShotAlphaClip: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: name, withExtension: "mov") else { return view }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        // Same as the looping clips: without these the transparency composites
        // against black and Rex sits in a dark box.
        view.playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        view.playerLayer.isOpaque = false
        view.backgroundColor = .clear
        view.isOpaque = false
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
