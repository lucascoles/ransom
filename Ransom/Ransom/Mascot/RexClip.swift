import AVFoundation
import SwiftUI

/// Rex, alive: a short clip on a loop rather than a still.
///
/// Two poses have one. The rest stay as artwork, because a mascot that twitches
/// on every screen stops being a character and becomes a distraction - and the
/// two that earn it are the two you sit and look at, waiting or resting.
///
/// The bundled clips are boomerangs - forward then back - so they loop with no
/// seam. A generated clip almost never ends where it began, and the jump at the
/// join is exactly the sort of thing that reads as a bug.
struct RexClip: View {
    var name: String
    var size: CGFloat

    /// A still frame is the honest fallback, not a blank space: the clips are
    /// bundled, so a miss here means a build problem rather than a runtime one,
    /// and the pose still has to render.
    var fallback: RexPose

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let aspect: CGFloat = 640.0 / 451.0

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "mov"), !reduceMotion {
                PingPongClip(url: url)
            } else {
                // Reduce Motion gets the still. Someone who has asked the system
                // to stop things moving has not made an exception for mascots.
                RexImage(pose: fallback, size: size)
            }
        }
        .frame(width: size, height: size * Self.aspect)
    }
}

/// Loops a clip, forever, with no seam to hide.
///
/// The clips are boomerangs - every frame forward then every frame back - baked
/// that way at build time, so the last frame is the first one and an ordinary
/// looping player is all that is needed.
///
/// The first version tried to do that turn at runtime by setting `rate = -1` at
/// the end. It played once and stopped: most H.264 encodes cannot be played in
/// reverse at all, and `AVPlayerItemDidPlayToEndTime` never fires at the *start*
/// of a clip anyway, so nothing was there to turn it round again. Doing the work
/// once, offline, beats asking the player for something it will not do.
private struct PingPongClip: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        // Decorative video must never duck whatever the user is listening to.
        queue.actionAtItemEnd = .advance
        context.coordinator.looper = AVPlayerLooper(player: queue, templateItem: item)
        view.playerLayer.player = queue
        view.playerLayer.videoGravity = .resizeAspect
        // The clips carry an alpha channel, so the layer must not paint anything
        // behind them - left opaque, iOS composites the transparency against
        // black and the character sits in a dark box on a light screen.
        view.playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        view.playerLayer.isOpaque = false
        view.backgroundColor = .clear
        view.isOpaque = false
        queue.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        // Coming back from the background leaves the player paused.
        (view.playerLayer.player as? AVQueuePlayer)?.play()
    }

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
