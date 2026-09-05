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

/// Types a beat's copy on, one character at a time.
///
/// Three lines of setup delivered as finished blocks are read in a glance and
/// absorbed by nobody. Typing sets the pace of the joke: the reader arrives at
/// the punchline at the moment it lands rather than a second before it.
///
/// The opener is typed first and smaller, then the line under it, so "This is
/// Rex" has landed before he is accused of anything.
private struct TypedLines: View {
    var lead: String?
    var line: String
    /// Skip straight to the finished text - Reduce Motion, or an impatient tap.
    var isInstant: Bool
    var onComplete: () -> Void

    /// One progress per line, driven in sequence.
    ///
    /// A single shared value looked right on paper and typed both lines at once:
    /// each renderer interpolates its own copy over the same window, so deriving
    /// "where is this line up to" from one number loses the ordering entirely.
    /// Two values, animated one after the other, is what actually sequences them.
    @State private var leadProgress: Double = 0
    @State private var lineProgress: Double = 0

    /// Unhurried on purpose. Fast typing is just a stutter before the text
    /// appears; at this pace the reader is reading along with it.
    private let perCharacter: Double = 0.055
    /// A pause between the opener and the line, so they read as two thoughts.
    private let betweenLines: Double = 0.4

    private var leadCount: Int { lead?.count ?? 0 }
    private var leadDuration: Double { Double(leadCount) * perCharacter }
    private var lineDuration: Double { Double(line.count) * perCharacter }
    private var totalDuration: Double {
        leadDuration + (leadCount > 0 ? betweenLines : 0) + lineDuration
    }

    var body: some View {
        VStack(spacing: 6) {
            if let lead {
                typed(lead, progress: leadProgress)
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.inkSoft)
            }

            typed(line, progress: lineProgress)
                .font(RansomFont.title(24))
                .foregroundStyle(Palette.ink)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: line) {
            leadProgress = 0
            lineProgress = 0
            guard !isInstant else {
                leadProgress = 1
                lineProgress = 1
                onComplete()
                return
            }

            if leadCount > 0 {
                // Linear, because the per-glyph spring below supplies the
                // character; easing the reveal too would make it arrive in a rush.
                withAnimation(.linear(duration: leadDuration)) { leadProgress = 1 }
                try? await Task.sleep(for: .seconds(leadDuration + betweenLines))
                if Task.isCancelled { return }
            }

            withAnimation(.linear(duration: lineDuration)) { lineProgress = 1 }
            try? await Task.sleep(for: .seconds(lineDuration))
            if !Task.isCancelled { onComplete() }
        }
        .onChange(of: isInstant) { _, instant in
            guard instant else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                leadProgress = 1
                lineProgress = 1
            }
        }
    }

    /// One line's worth of glyphs, keeping native text layout so wrapping,
    /// kerning and alignment stay the system's job rather than mine.
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
private struct TypeOnRenderer: TextRenderer, Animatable {
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
            // across the whole 0...1 instead left the last few characters frozen
            // part-way through their fade, which reads as permanently blurred
            // rather than as still arriving.
            let start = (Double(index) / count) * (1 - window)
            let t = min(1, max(0, (progress - start) / window))
            guard t > 0 else { continue }

            // Overshoot then settle: back-ease out, the same shape a spring
            // gives, without the cost of one animator per character.
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
