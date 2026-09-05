import AVFoundation
import SwiftUI

/// The cold open: three taps that name the problem before the app asks for a thing.
///
/// Rex is the one with the phone problem, not the user. Telling it as his story
/// lets the last line turn on the reader without ever having accused them of
/// anything — and the joke does the real work, because the reason he can't put it
/// down is the same reason a T-rex is funny doing push-ups. The product thesis
/// arrives as a punchline instead of a pitch.
///
/// Each beat plays as a short looping clip and holds there for as long as the
/// reader wants. The tap does one thing only — move to the next beat — so nobody
/// is ever waiting on a timeline to finish before they can go on, and nobody is
/// hurried off a line they're still reading.
struct ColdOpenStep: View {
    var onFinish: () -> Void

    @State private var beat = 0
    /// Whether the current beat's text has finished typing. A tap completes the
    /// typing before it advances, so an impatient reader never skips a line they
    /// haven't seen.
    @State private var isTextComplete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Beat {
        let image: String
        let clip: String
        /// Optional opener, typed first and smaller. Only the first beat has one:
        /// nobody has met Rex yet, and a story about someone you haven't been
        /// introduced to is just a stranger with a phone.
        let lead: String?
        let line: String
    }

    private let beats: [Beat] = [
        Beat(image: "ColdOpen1", clip: "ColdOpen1",
             lead: "This is Rex.",
             line: "He picked up his phone four hours ago."),
        Beat(image: "ColdOpen2", clip: "ColdOpen2",
             lead: nil,
             line: "He tries to put it down, but his arms are too short."),
        Beat(image: "ColdOpen3", clip: "ColdOpen3",
             lead: nil,
             line: "You know how he feels, don't you."),
    ]

    private var clipURL: URL? {
        Bundle.main.url(forResource: beats[beat].clip, withExtension: "mp4")
    }

    /// The exact background the clips were rendered on.
    ///
    /// Multiply keys pure white onto the canvas, which is what the intro clip
    /// relies on — but these clips come back at #FAFAFA, not #FFFFFF, so
    /// multiplying them laid a faintly cooler, darker rectangle over the page.
    /// Painting the screen in the clips' own colour instead makes the seam
    /// disappear exactly, with no filtering and no shift in Rex's colours. It sits
    /// four units of blue away from `Palette.canvas`, which no eye will find.
    private static let clipBackground = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)

    var body: some View {
        ZStack {
            Self.clipBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                TypedLines(
                    lead: beats[beat].lead,
                    line: beats[beat].line,
                    isInstant: reduceMotion || isTextComplete,
                    onComplete: { isTextComplete = true }
                )
                .padding(.horizontal, 34)
                // A fixed slot: the lines wrap to different heights and the first
                // beat carries two of them, so without it the art walks up and
                // down the screen between beats.
                .frame(height: 132)
                .id("line\(beat)")
                .transition(textTransition)

                ZStack {
                    if reduceMotion {
                        // The stills came back at pure white, and multiplying white
                        // is the identity — so this lands on exactly the screen
                        // colour whatever that colour is.
                        Image(beats[beat].image)
                            .resizable()
                            .scaledToFit()
                            .blendMode(.multiply)
                    } else if let clipURL {
                        // Drawn straight, no blend: the screen is already painted
                        // in the clip's own background colour.
                        LoopingClip(url: clipURL)
                    }
                }
                .id("art\(beat)")
                .transition(artTransition)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .padding(.horizontal, 18)

                Spacer(minLength: 0)

                Text(beat == beats.count - 1 ? "TAP TO BEGIN" : "TAP TO CONTINUE")
                    .font(RansomFont.caption(12))
                    .tracking(1.4)
                    .foregroundStyle(Palette.brand)
                    .padding(.bottom, 34)
            }

            // Skipping is one tap and carries no penalty. Someone who already knows
            // they have this problem shouldn't have to sit through being told.
            VStack {
                HStack {
                    Spacer()
                    Button("Skip", action: onFinish)
                        .font(RansomFont.caption(14))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.trailing, Metrics.screenPadding)
                        .padding(.top, 8)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: next)
    }

    private var artTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity.combined(with: .scale(scale: 1.04))
        )
    }

    private var textTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .offset(y: -14))
        )
    }

    private func next() {
        // First tap finishes the sentence, second moves on.
        guard isTextComplete || reduceMotion else {
            Haptics.tap()
            isTextComplete = true
            return
        }
        guard beat < beats.count - 1 else {
            Haptics.select()
            onFinish()
            return
        }
        Haptics.tap()
        isTextComplete = false
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                   : .spring(response: 0.45, dampingFraction: 0.82)) {
            beat += 1
        }
    }
}

/// Plays a bundled clip on a loop.
///
/// Looping rather than one-shot because a beat that stops dead reads as the app
/// having hung, and the reader is meant to be able to sit on a line as long as
/// they like before tapping on.
private struct LoopingClip: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        // Never let a decorative clip duck the user's music.
        queue.actionAtItemEnd = .advance
        context.coordinator.looper = AVPlayerLooper(player: queue, templateItem: item)
        view.playerLayer.player = queue
        view.playerLayer.videoGravity = .resizeAspect
        queue.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        (view.playerLayer.player as? AVQueuePlayer)?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The copy for one beat: an optional smaller opener, then the line.
private struct TypedLines: View {
    var lead: String?
    var line: String
    var isInstant: Bool
    var onComplete: () -> Void

    var body: some View {
        TypedStack(
            lines: [
                lead.map { TypedLine.line($0, RansomFont.headline(17), Palette.inkSoft) },
                // A pause between the opener and the line, so they read as two
                // thoughts rather than one run-on.
                TypedLine.line(line, RansomFont.title(24), Palette.ink,
                               leadIn: lead == nil ? 0 : 0.4),
            ].compactMap { $0 },
            isInstant: isInstant,
            onComplete: onComplete
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
