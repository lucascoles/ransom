import AVFoundation
import SwiftUI

/// Rex's intro animation: he kicks the phone away, does a push-up, comes back bigger.
/// The whole product argument in six seconds, before a word of copy is read.
///
/// The clip is rendered on white rather than with an alpha channel, because no video
/// codec Apple ships to iOS carries transparency reliably. `.blendMode(.multiply)`
/// does the keying instead: white multiplied against the canvas leaves the canvas
/// untouched, so the background disappears without a matte. It only works because
/// the canvas is lighter than every colour in the artwork.
struct RexIntroVideo: View {
    /// Width. Height follows from the clip's own aspect — framing a 16:9 clip in a
    /// square letterboxes it, which shrinks Rex and leaves dead space the multiply
    /// blend can't hide.
    var size: CGFloat = 240
    /// Deliberately squarer than the 16:9 clip. Paired with `.resizeAspectFill`
    /// below it centre-crops the wide empty margins, so Rex fills the space
    /// instead of floating in it — the crop still clears him and the phone.
    var aspect: CGFloat = 4.0 / 3.0

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player {
                VideoLayerView(player: player)
                    .blendMode(.multiply)
            } else {
                // Whatever happens with the asset, the screen still has a mascot.
                RexImage(pose: .flex, size: size / aspect)
            }
        }
        .frame(width: size, height: size / aspect)
        .allowsHitTesting(false)
        .onAppear(perform: start)
        .onDisappear {
            player?.pause()
            player = nil
            looper = nil
        }
    }

    private func start() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "RexIntro", withExtension: "mp4")
        else { return }

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        // Never let the clip duck the user's music.
        queue.actionAtItemEnd = .advance

        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        queue.play()
    }
}

/// A bare `AVPlayerLayer`. SwiftUI's `VideoPlayer` draws playback controls and a
/// background that can't be turned off, both of which are wrong for a mascot.
private struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
