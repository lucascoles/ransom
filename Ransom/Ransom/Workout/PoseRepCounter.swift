import AVFoundation
import Combine
import Foundation
import Observation
import Vision

/// Counts reps by watching the body, not the phone.
///
/// The sensor detectors this replaces are all trivially cheatable — a hand waved
/// over the proximity sensor is a push-up, a shaken phone is ten jumping jacks.
/// That matters more than it sounds: if the count can be faked then the lifetime
/// figure, the streak and the whole ledger are decorative, and a user who works
/// that out has no reason left to open the app.
///
/// This runs Vision's body-pose request on the front camera, entirely on device.
/// No frame is written to disk, uploaded, or kept beyond the moment it's measured.
@Observable
final class PoseRepCounter: NSObject {

    enum State: Equatable {
        case idle
        /// Camera is up but no usable body is in frame.
        case searching
        /// Tracking a body and counting.
        case tracking
        /// Something is wrong the user can fix.
        case blocked(String)
    }

    private(set) var reps = 0
    private(set) var state: State = .idle
    /// 0 = top of the rep, 1 = bottom. Drives Rex, same as the sensor path did.
    private(set) var depth: Double = 0
    /// Nil when form is fine; otherwise one short correction.
    private(set) var formHint: String?
    /// How much of the required range the last rep actually covered, 0-1.
    private(set) var lastRepQuality: Double = 0
    /// Reps rejected for not covering the range. Surfaced so the count feels fair.
    private(set) var rejectedReps = 0

    let exercise: Exercise
    let target: Int

    var isComplete: Bool { reps >= target }
    var progress: Double { target > 0 ? min(1, Double(reps) / Double(target)) : 0 }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ransom.pose", qos: .userInitiated)
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    // Rep state machine
    private var isDown = false
    private var repFloor: Double = 0
    private var repCeiling: Double = 0
    private var lastRepAt: Date = .distantPast
    private var lowConfidenceFrames = 0

    /// A rep must travel at least this much of the observed range to count. This is
    /// the anti-cheat: small bounces and shuffles never accumulate into a rep.
    private let requiredRange: Double = 0.45
    /// Vision joint confidence below this is treated as "not seeing you properly".
    private let minimumConfidence: Float = 0.3

    init(exercise: Exercise, target: Int) {
        self.exercise = exercise
        self.target = target
        super.init()
    }

    // MARK: - Lifecycle

    func start() async {
        guard await requestCameraAccess() else {
            state = .blocked("Ransom needs the camera to count your reps. You can still tap to count.")
            return
        }
        configureSession()
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        state = .searching
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        state = .idle
    }

    /// Always available. A missed rep is the app's fault, never the user's.
    func registerManualRep() {
        guard reps < target else { return }
        commitRep(quality: 1)
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureSession() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium   // Pose estimation doesn't need more.

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
    }

    /// Exposed so the workout screen can show the user what the camera sees —
    /// people trust a counter far more when they can see it looking at them.
    var previewSession: AVCaptureSession { session }

    // MARK: - Measurement

    /// The single number each movement is judged on, normalised 0-1, where 1 is
    /// the bottom of the rep. Derived from joint positions rather than the phone.
    private func measure(_ observation: VNHumanBodyPoseObservation) -> (value: Double, hint: String?)? {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? observation.recognizedPoint(joint),
                  p.confidence > minimumConfidence else { return nil }
            return p.location
        }

        switch exercise.sensing {
        case .proximity:   // push-ups: how close the shoulders are to the ground
            guard let ls = point(.leftShoulder), let rs = point(.rightShoulder),
                  let lw = point(.leftWrist), let rw = point(.rightWrist) else { return nil }
            let shoulder = (ls.y + rs.y) / 2
            let wrist = (lw.y + rw.y) / 2
            // Vision's origin is bottom-left, so a smaller gap means lower chest.
            let gap = abs(shoulder - wrist)
            let hint = gap > 0.45 ? "Get lower — chest toward the floor." : nil
            return (1 - min(1, gap / 0.5), hint)

        case .impact:      // jumping jacks: wrist separation above the head
            guard let lw = point(.leftWrist), let rw = point(.rightWrist),
                  let neck = point(.neck) else { return nil }
            let armsUp = (lw.y > neck.y && rw.y > neck.y) ? 1.0 : 0.0
            let spread = min(1, abs(lw.x - rw.x) / 0.6)
            return (max(armsUp, spread), nil)

        case .tilt:        // squats and sit-ups: hip travel relative to the knee
            guard let lh = point(.leftHip), let rh = point(.rightHip),
                  let lk = point(.leftKnee), let rk = point(.rightKnee) else { return nil }
            let hip = (lh.y + rh.y) / 2
            let knee = (lk.y + rk.y) / 2
            let drop = 1 - min(1, max(0, (hip - knee) / 0.35))
            let hint = drop < 0.3 ? "Deeper — hips to knee height." : nil
            return (drop, hint)
        }
    }

    /// Rep state machine with range gating. A rep only counts when the movement
    /// travels down past the threshold AND returns, covering enough of the range.
    private func consume(value: Double, hint: String?) {
        depth = value
        formHint = hint

        if !isDown {
            repCeiling = min(repCeiling, value)
            if value > 0.65 {
                isDown = true
                repFloor = value
            }
        } else {
            repFloor = max(repFloor, value)
            if value < 0.3 {
                let range = repFloor - repCeiling
                isDown = false
                repCeiling = value
                if range >= requiredRange {
                    commitRep(quality: min(1, range / 0.8))
                } else {
                    // Seen, judged, and not counted — say so rather than ignoring it.
                    rejectedReps += 1
                    formHint = "That one didn't go far enough."
                }
            }
        }
    }

    private func commitRep(quality: Double) {
        guard Date().timeIntervalSince(lastRepAt) > 0.4 else { return }
        lastRepAt = .now
        lastRepQuality = quality
        reps += 1
        Haptics.rep()
        if reps >= target { stop() }
    }
}

// MARK: - Frame handling

extension PoseRepCounter: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform([poseRequest])

        guard let observation = poseRequest.results?.first,
              let reading = measure(observation) else {
            lowConfidenceFrames += 1
            if lowConfidenceFrames > 30 {
                Task { @MainActor in
                    self.state = .searching
                    self.formHint = "Prop the phone up so it can see you."
                }
            }
            return
        }

        lowConfidenceFrames = 0
        Task { @MainActor in
            if self.state != .tracking { self.state = .tracking }
            self.consume(value: reading.value, hint: reading.hint)
        }
    }
}
