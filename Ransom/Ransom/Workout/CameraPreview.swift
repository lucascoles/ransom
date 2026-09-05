import AVFoundation
import SwiftUI
import UIKit

/// The live self-view the counter sits on.
///
/// Seeing yourself is what makes the count believable: when a rep doesn't
/// register, the user can see *why* — they're out of frame, or too dark, or the
/// phone is aimed at the ceiling. Without it a missed rep just looks broken.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach(session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Re-attaching is cheap and idempotent. It matters because the layer's
        // connection doesn't exist until the session has an input, which happens
        // asynchronously after the camera permission prompt — so the first attach
        // can silently land before there's anything to orient.
        uiView.attach(session: session)
    }

    /// Backing the view with `AVCaptureVideoPreviewLayer` directly, rather than
    /// adding a sublayer, keeps the preview sized to the view through layout
    /// changes without any manual frame bookkeeping.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        func attach(session: AVCaptureSession) {
            if previewLayer.session !== session {
                previewLayer.session = session
                previewLayer.videoGravity = .resizeAspectFill
            }

            guard let connection = previewLayer.connection else { return }

            // Mirrored, because an un-mirrored self-view feels wrong to everyone
            // who has ever used a mirror. Display only — the pose request reads the
            // unmirrored buffer, so Vision's left and right joints stay correct,
            // and the overlay mirrors its own coordinates to match.
            if connection.isVideoMirroringSupported, !connection.isVideoMirrored {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }

            guard rotationCoordinator == nil,
                  let device = session.inputs
                      .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                      .first
            else { return }

            // Let AVFoundation work out which way is up. A hardcoded 90 degrees is
            // right on some device-and-camera combinations and a sideways picture
            // on others, which is exactly the bug this replaces.
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            applyRotation()
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor in self?.applyRotation() }
            }
        }

        private func applyRotation() {
            guard let coordinator = rotationCoordinator,
                  let connection = previewLayer.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            guard connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}

/// The tracking skeleton: bones across the shoulders and down both arms, drawn
/// over the user's own body.
///
/// This is the whole trust mechanism. A number counting up on its own could be
/// counting anything; lines that stick to your shoulders and bend with your
/// elbows are visible proof the app is watching *you*.
struct PoseSkeletonView: View {
    var frame: PoseFrame
    /// The preview is mirrored for the self-view, so the joints have to be too or
    /// the skeleton lands on the wrong side of the body.
    var mirrored: Bool = true

    /// What gets drawn, which is deliberately less than what gets measured.
    ///
    /// The detector still tracks hips, knees and ankles - the legs are the only
    /// way to tell a push-up from a knee push-up, so they matter enormously - but
    /// drawing them turned the overlay into a full marionette over a body that is
    /// mostly out of frame anyway. The arms and the line across the shoulders are
    /// the parts a user can check at a glance, and they're the parts the rep is
    /// actually judged on.
    private static let drawnBones: [(PoseFrame.Joint, PoseFrame.Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
    ]

    private static let drawnJoints: Set<PoseFrame.Joint> = [
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
    ]

    var body: some View {
        Canvas { context, size in
            let placed = place(in: size)

            for (a, b) in Self.drawnBones {
                guard let start = placed[a], let end = placed[b] else { continue }
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                // Drawn twice: a dark casing so the bone survives a bright shirt
                // or a sunlit floor, then the brand line over it.
                context.stroke(path, with: .color(.black.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round))
                context.stroke(path, with: .color(.white),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            for (joint, point) in placed where Self.drawnJoints.contains(joint) {
                let dot = CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11)
                context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.3)))
                context.fill(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)),
                             with: .color(Palette.brand))
            }
        }
        .allowsHitTesting(false)
    }

    /// Reproduces `AVLayerVideoGravity.resizeAspectFill`: the video is scaled to
    /// cover the view and centre-cropped. Getting this wrong is what floats a
    /// skeleton beside the body rather than on it.
    private func place(in size: CGSize) -> [PoseFrame.Joint: CGPoint] {
        guard size.width > 0, size.height > 0, frame.aspect > 0 else { return [:] }

        let scale = max(size.width / frame.aspect, size.height)
        let drawn = CGSize(width: frame.aspect * scale, height: scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2,
                             y: (size.height - drawn.height) / 2)

        return frame.joints.reduce(into: [:]) { result, entry in
            let x = origin.x + entry.value.x * drawn.width
            result[entry.key] = CGPoint(x: mirrored ? size.width - x : x,
                                        y: origin.y + entry.value.y * drawn.height)
        }
    }
}

/// The framed self-view: the video, the skeleton on top of it, and the count.
/// Sized to sit in the layout rather than take the whole screen.
struct CameraWindow: View {
    let session: AVCaptureSession
    var pose: PoseFrame?
    var reps: Int
    var target: Int
    /// Shown while the camera hasn't found anyone yet.
    var status: String?

    var body: some View {
        ZStack {
            CameraPreview(session: session)

            if let pose {
                PoseSkeletonView(frame: pose)
                    .transition(.opacity)
            }

            VStack {
                Spacer()
                // The count sits on the video, where the user is already looking.
                Text("\(reps) / \(target)")
                    .font(RansomFont.counter(46))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(reps)))
                    .animation(.snappy(duration: 0.2), value: reps)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                    .padding(.bottom, 16)
            }

            if let status {
                Text(status)
                    .font(RansomFont.caption(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .transition(.opacity)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .animation(.easeInOut(duration: 0.2), value: status)
    }
}
