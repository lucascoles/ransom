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

/// The tracking skeleton: the bones the rep is judged on, drawn over the user's
/// own body. Arms and the line across the shoulders for push-ups; legs and the
/// line across the hips for squats.
///
/// This is the whole trust mechanism. A number counting up on its own could be
/// counting anything; lines that stick to your shoulders and bend with your
/// elbows - or sit on your hips and fold with your knees - are visible proof the
/// app is watching *you*.
struct PoseSkeletonView: View {
    var frame: PoseFrame
    var exercise: Exercise
    /// The preview is mirrored for the self-view, so the joints have to be too or
    /// the skeleton lands on the wrong side of the body.
    var mirrored: Bool = true

    /// What gets drawn, which is deliberately less than what gets measured.
    ///
    /// The detector tracks the whole body for both movements, but drawing all of
    /// it turned the overlay into a full marionette. What earns a line is what
    /// the rep is judged on, because that is what a user can check against their
    /// own body at a glance. For push-ups that is the arms and the shoulder line
    /// - the legs are measured for the kneeling gate but a body lying towards
    /// the lens is mostly out of frame anyway. For squats it is the legs and the
    /// hip line: the rep is hips falling towards knees, and a skeleton over the
    /// arms would be showing the one part of the body the count ignores.
    private static func drawnBones(for exercise: Exercise) -> [(PoseFrame.Joint, PoseFrame.Joint)] {
        switch exercise {
        case .squats:
            return [
                (.leftHip, .rightHip),
                (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
                (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
            ]
        case .pushUps, .steps:
            return [
                (.leftShoulder, .rightShoulder),
                (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
                (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            ]
        }
    }

    private static func drawnJoints(for exercise: Exercise) -> Set<PoseFrame.Joint> {
        switch exercise {
        case .squats:
            return [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .pushUps, .steps:
            return [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        }
    }

    var body: some View {
        let bones = Self.drawnBones(for: exercise)
        let joints = Self.drawnJoints(for: exercise)

        Canvas { context, size in
            let placed = place(in: size)

            for (a, b) in bones {
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

            for (joint, point) in placed where joints.contains(joint) {
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
    /// Decides which bones the skeleton draws.
    let exercise: Exercise
    var pose: PoseFrame?
    var reps: Int
    var target: Int
    /// Shown while the camera hasn't found anyone yet.
    var status: String?
    /// Whether the count is actually running. A bright count over a counter that
    /// hasn't armed yet is a promise the screen can't keep: people start their
    /// set against it and lose the first reps.
    var isLive: Bool = true

    var body: some View {
        ZStack {
            CameraPreview(session: session)

            if let pose {
                PoseSkeletonView(frame: pose, exercise: exercise)
                    .transition(.opacity)
            }

            VStack {
                Spacer()
                // The count sits on the video, where the user is already looking.
                Text("\(reps) / \(target)")
                    .font(RansomFont.counter(46))
                    .foregroundStyle(.white.opacity(isLive ? 1 : 0.4))
                    .contentTransition(.numericText(value: Double(reps)))
                    .animation(.snappy(duration: 0.2), value: reps)
                    .animation(.easeInOut(duration: 0.2), value: isLive)
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
