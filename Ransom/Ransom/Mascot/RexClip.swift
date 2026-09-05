import AVFoundation
import SwiftUI

/// Rex, alive: a short clip on a loop rather than a still.
///
/// Two poses have one. The rest stay as artwork, because a mascot that twitches
/// on every screen stops being a character and becomes a distraction - and the
/// two that earn it are the two you sit and look at, waiting or resting.
///
/// The clip is played forward and then backward, which is why nothing has to be
/// done to make the ends match. A generated clip almost never loops cleanly, and
/// the jump at the seam is exactly the sort of thing that reads as a bug; ping
/// ponging it means the only frame that has to join is the one it started on.
struct RexClip: View {
    var name: String
    var size: CGFloat

    /// A still frame is the honest fallback, not a blank space: the clips are
    /// bundled, so a miss here means a build problem rather than a runtime one,
    /// and the pose still has to render.
    var fallback: RexPose

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let aspect: CGFloat = 640.0 / 451.0

    /// The generated clips render their flat background at 248,248,246 while the
    /// app's canvas is 251,250,246 - close enough to look identical in isolation
    /// and far enough to show as a faint pale square sitting on the screen. A
    /// three-point lift matches them; the same lift on Rex himself is nowhere
    /// near visible, which is why this is cheaper than re-rendering the clips.
    private static let backgroundLift = 3.0 / 255.0

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp4"), !reduceMotion {
                PingPongClip(url: url)
                    .brightness(Self.backgroundLift)
            } else {
                // Reduce Motion gets the still. Someone who has asked the system
                // to stop things moving has not made an exception for mascots.
                RexImage(pose: fallback, size: size)
            }
        }
        .frame(width: size, height: size * Self.aspect)
    }
}

/// Plays a clip forward, then backward, forever.
private struct PingPongClip: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVPlayer(url: url)
        player.isMuted = true
        // Decorative video must never duck whatever the user is listening to.
        player.actionAtItemEnd = .none
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        context.coordinator.attach(to: player)
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var observer: NSObjectProtocol?
        private var isReversing = false

        func attach(to player: AVPlayer) {
            self.player = player
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in self?.turnAround() }
        }

        /// At each end, seek back to that end and play the other way.
        ///
        /// `rate = -1` needs the playhead off the boundary or it refuses to move,
        /// hence the seek before the rate change rather than after it.
        private func turnAround() {
            guard let player, let item = player.currentItem else { return }
            isReversing.toggle()
            if isReversing {
                player.seek(to: item.duration, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.rate = -1
                }
            } else {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.rate = 1
                }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            player = nil
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
