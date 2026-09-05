// AVCaptureSession is not Sendable, but it is documented as safe to drive from
// one serial queue, which is exactly what `queue` is and the only place the
// session is ever started or stopped.
@preconcurrency import AVFoundation
import Foundation
import Observation
import UIKit
import Vision

/// Counts push-ups by watching the body, not the phone.
///
/// The sensor detectors this replaces are all trivially cheatable — a hand waved
/// over the proximity sensor is a push-up, a shaken phone is ten jumping jacks.
/// That matters more than it sounds: if the count can be faked then the lifetime
/// figure, the streak and the whole ledger are decorative, and a user who works
/// that out has no reason left to open the app.
///
/// **Push-ups only, deliberately.** One movement counted properly is worth five
/// counted badly. Anything else falls straight through to `RepEngine`.
///
/// Runs Vision's body-pose request on the front camera, entirely on device. No
/// frame is written to disk, uploaded, or kept beyond the moment it's measured.
///
/// Four things make this work where a naive implementation misses half the set:
///
///  1. **Head-on framing.** The phone stands vertically facing the user, past
///     their hands. Vision's model expects an upright body, and head-on a push-up
///     reads as one — head at the top, hands at the bottom. Filmed from the side
///     the same body lies flat across the frame, the pose the model is worst at.
///  2. **Elbows decide, shoulders corroborate.** Elbow angle is the only measure
///     that means "push-up" — so no rep is banked without it, however convincing
///     the rest of the body looks. Shoulder height is tracked alongside it and has
///     to agree, but it can never carry a rep alone: a downward dog drops the
///     shoulders through a huge range on locked-out arms, and any check that lets
///     shoulder travel vote by itself counts that as a set.
///  3. **Rolling calibration.** Everyone's range is different and the camera never
///     sees it square on, so the range is learned live — from *percentiles of the
///     last few seconds*, not the extremes ever seen. An all-time min and max is
///     the trap: one glitched frame widens the range permanently, every later rep
///     covers a fraction of it, and the counter goes quiet for the rest of the set.
///  4. **Hysteresis.** Separate thresholds going down and coming up, so a body
///     hovering near one level can't rattle out reps.
///  5. **Absolute travel gates.** Self-calibration is what makes the count work
///     for every body, and also what makes it forgeable: a signal that rescales
///     to whatever you're doing can't tell a full push-up from a twitch. So the
///     timing comes from the calibrated signal, and the *verdict* comes from raw
///     movement — degrees of elbow bend and shoulder height in shoulder-widths,
///     both of which have to clear a fixed bar before a rep is banked.
@Observable
final class PoseRepCounter: NSObject {

    /// Mirrors `RepEngine.Phase` so the workout screen can drive either counter
    /// through the same flow.
    enum Phase: Equatable {
        case idle
        case counting
        case finished
    }

    /// What the camera can see right now. Separate from `phase`, which is about
    /// the set; this is about whether we have eyes on the user.
    enum Tracking: Equatable {
        case idle
        /// Camera is up but no usable body is in frame.
        case searching
        /// Watching a body, still learning how far this user travels.
        case calibrating
        /// Tracking a body and counting.
        case tracking
        /// Something is wrong that the user can fix, or the camera is unavailable.
        case blocked(String)
    }

    private(set) var reps = 0
    private(set) var phase: Phase = .idle
    private(set) var tracking: Tracking = .idle
    /// 0 = top of the rep, 1 = bottom. Drives Rex, same as the sensor path did.
    private(set) var depth: Double = 0
    /// Nil when form is fine; otherwise one short correction.
    private(set) var formHint: String?
    /// Bounces rejected as too fast to be real. Kept so the count can be defended.
    private(set) var rejectedReps = 0
    /// The arms as last seen, for the skeleton drawn over the preview. Seeing the
    /// lines snap onto their own body is what tells a user it's really watching —
    /// a bare number could be counting anything.
    private(set) var poseFrame: PoseFrame?
    /// Live read of the detector, shown only in debug builds. Tuning rep detection
    /// blind is guesswork; this is how a missed rep gets diagnosed.
    private(set) var diagnostics: String?

    let exercise: Exercise
    let target: Int

    var isComplete: Bool { reps >= target }
    var progress: Double { target > 0 ? min(1, Double(reps) / Double(target)) : 0 }
    var elapsedSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }

    /// True once the camera has been ruled out, so the screen can fall back to
    /// the sensor counter instead of leaving the user with nothing.
    var isBlocked: Bool { if case .blocked = tracking { return true }; return false }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ransom.pose", qos: .userInitiated)
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var startedAt = Date()

    /// Apple's own answer to "which way up is this camera?". Hardcoding portrait
    /// as 90 degrees is the classic way to get a sideways feed: the correct angle
    /// depends on the device and on which camera is running.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var videoConnection: AVCaptureConnection?

    /// The buffer is already rotated upright by the rotation coordinator, so the
    /// request reads it as-is. Keeping this identical to what the preview shows is
    /// what lets the skeleton overlay land on the body instead of beside it.
    private let visionOrientation: CGImagePropertyOrientation = .up

    /// Last confident position of each joint.
    ///
    /// Joints drop out constantly and briefly: a face crosses the chest and takes
    /// the shoulder line with it, a forearm hides a wrist at the bottom of every
    /// rep. Discarding those frames is what loses reps — the movement never
    /// stopped, only the view of it did. Holding the last position for a fraction
    /// of a second bridges the blink instead of throwing the rep away.
    private var jointMemory: [Joint: (point: CGPoint, at: Date)] = [:]
    /// Longer than it looks like it needs to be, for close-grip reps: at the
    /// bottom the hands sit beside the head and the wrists disappear behind it
    /// for a few frames, which is exactly the moment the elbow angle matters most.
    private let jointHold: TimeInterval = 0.7
    /// Shoulder width is the yardstick the drop signal is measured in, and it
    /// barely changes during a set — so once seen it's remembered, and a single
    /// visible shoulder is enough to keep measuring.
    private var lastShoulderWidth: Double?
    /// Where the person being counted was last seen, so the count stays with them
    /// when someone else walks into shot.
    private var lockedSubjectCentre: CGPoint?

    /// Width / height of the frames being delivered. Vision reports joints in a
    /// normalised unit square, so on a non-square frame the x axis is compressed
    /// relative to y and any angle measured in those coordinates is skewed.
    private var frameAspect: Double = 1

    // MARK: Signal conditioning

    /// Elbow angle in degrees: straight at the top of a push-up, bent at the
    /// bottom. The truest signal, when the wrists are visible.
    private var elbowTrack = SignalTrack(minimumSpan: 18, smoothing: 0.6)
    /// Shoulder height measured in shoulder-widths: rises as the chest drops.
    /// Needs only the two shoulders, the joints Vision is most confident about,
    /// so it keeps counting through everything that hides the wrists.
    private var dropTrack = SignalTrack(minimumSpan: 0.10, smoothing: 0.6)

    /// What actually happened during the rep in progress, in raw units.
    ///
    /// This is the anti-cheat. The normalised signal deliberately rescales itself
    /// to whatever the user is doing, which is what makes it count honest reps of
    /// any depth — and also what makes a shoulder twitch look identical to a full
    /// push-up once the window contains nothing but twitches. Absolute movement is
    /// the thing a rescaling signal can never tell you, so it's checked separately
    /// before any rep is banked.
    private struct RepWindow {
        var elbowLow = Double.infinity
        var elbowHigh = -Double.infinity
        var dropLow = Double.infinity
        var dropHigh = -Double.infinity
        var elbowFrames = 0
        var dropFrames = 0
        var totalFrames = 0
        var startedDownAt: Date?

        mutating func observe(elbow: Double?, drop: Double?) {
            totalFrames += 1
            if let elbow {
                elbowFrames += 1
                elbowLow = min(elbowLow, elbow)
                elbowHigh = max(elbowHigh, elbow)
            }
            if let drop {
                dropFrames += 1
                dropLow = min(dropLow, drop)
                dropHigh = max(dropHigh, drop)
            }
        }

        /// A signal only gets a vote if it was visible for a decent share of the
        /// rep. Two stray frames of a half-seen wrist shouldn't be able to veto a
        /// push-up that the shoulders tracked cleanly from start to finish.
        private func sawEnough(_ frames: Int) -> Bool {
            totalFrames > 0 && Double(frames) / Double(totalFrames) >= 0.3
        }

        var elbowTravel: Double? {
            guard sawEnough(elbowFrames), elbowHigh > elbowLow else { return nil }
            return elbowHigh - elbowLow
        }

        var dropTravel: Double? {
            guard sawEnough(dropFrames), dropHigh > dropLow else { return nil }
            return dropHigh - dropLow
        }

        /// Shoulders tracked for most of the rep, not merely glimpsed. Only then
        /// is a small drop evidence of a shallow rep rather than of a blink.
        var sawShouldersThroughout: Bool {
            totalFrames > 0 && Double(dropFrames) / Double(totalFrames) >= 0.7
        }

        /// The most bent the elbow got. Travel alone can be produced by a body
        /// that starts already folded; this insists the arm reached a real
        /// bottom position.
        var elbowBottom: Double? {
            guard sawEnough(elbowFrames), elbowLow.isFinite else { return nil }
            return elbowLow
        }

        /// Forgets the shoulder extremes gathered during the rest and restarts
        /// them from the moments just before the descent. The rest is where the
        /// user shifts, looks up, or sits back, none of which is a push-up, and
        /// all of which read as a huge drop if left in.
        mutating func rescopeDrop(to recent: [Double]) {
            dropLow = recent.min() ?? .infinity
            dropHigh = recent.max() ?? -.infinity
        }
    }

    private var repWindow = RepWindow()

    /// How far a real push-up moves. Degrees of elbow bend, and shoulder height in
    /// shoulder-widths. Both are well inside what a genuine rep covers — a full
    /// push-up bends the elbow through 70-90 degrees — and well outside what
    /// bouncing on the spot produces.
    private let minElbowTravel: Double = 35
    private let minDropTravel: Double = 0.12
    /// With no shoulder drop to corroborate it, the elbow has to clear a higher
    /// bar on its own.
    private let soloElbowTravel: Double = 45
    /// How bent the elbow has to get at the bottom. A real push-up finishes near
    /// a right angle; anything that keeps the arms locked out sits far above this
    /// however far the rest of the body travels.
    private let maxBottomAngle: Double = 145
    /// The relaxed elbow gates, unlocked only by a strong shoulder drop.
    ///
    /// Close-grip push-ups are the case that broke the elbow-only gates. With the
    /// elbows tucked, the forearm points straight at a head-on camera and the
    /// angle is measured on a foreshortened arm: in a real set, four of ten
    /// close-grip reps bottomed out at a *reading* of 137-147 degrees with only
    /// 25-31 degrees of travel, and every one was thrown out as "not deep
    /// enough" while the shoulders had visibly dropped 0.44-0.69 shoulder widths
    /// - the same as the reps that counted. The elbow was lying about depth and
    /// the shoulders were telling the truth.
    ///
    /// So when the shoulders drop this far, the elbow only has to show that the
    /// arms genuinely bent. The elbow is still not optional: a downward dog on
    /// locked arms drops the shoulders a long way with zero elbow travel and
    /// still fails here.
    private let strongDropTravel: Double = 0.35
    private let corroboratedElbowTravel: Double = 20
    private let corroboratedBottomAngle: Double = 155
    /// Nobody descends and returns in under a third of a second.
    private let minimumRepDuration: TimeInterval = 0.18
    /// How far back up the shoulders must come, as a share of the rep's own
    /// drop, before a rep the elbow has finished is banked.
    ///
    /// This is what tells a push-up from *getting into position*. Lowering
    /// oneself from kneeling into a plank bends and straightens the elbows just
    /// like a rep, but the shoulders finish at the bottom of their travel and
    /// stay there. A rep brings them back.
    private let minimumShoulderReturn = 0.25
    /// How long a finished rep waits for the shoulders to come back before it is
    /// refused.
    ///
    /// Checking the shoulders at the instant the elbow finished cost an honest
    /// rep: at the bottom of a close-grip push-up the wrists are hidden and the
    /// elbow reading can jump straight to "returned" while the chest is still on
    /// the floor. The shoulders followed a third of a second later. So the rep is
    /// held, not refused, and banks the moment they arrive; only shoulders that
    /// never come back lose it.
    private let shoulderReturnTimeout: TimeInterval = 1.0
    /// A rep judged this soon after its descent began is a twitch, not an attempt,
    /// and is refused without buzzing the phone or explaining itself.
    ///
    /// Two such twitches in one set - the elbow reading bouncing as the wrists
    /// reappeared after a rep, and a 16 degree shift at rest - each fired a
    /// warning haptic and a wrong correction ("too fast", "not deep enough") at a
    /// user who had done nothing. Real attempts, even shallow ones, took 0.8s or
    /// more; the user needs to hear about those.
    private let briefExcursion: TimeInterval = 0.5
    /// How far back before the elbow starts to bend the shoulders are measured
    /// from. In close grip the shoulders lead the elbow reading by up to 0.6s;
    /// anything older than this is the rest between reps, and a rest is where
    /// the user shifts about. Measured over a whole rest the "drop" reached 2.0
    /// shoulder widths without a single rep in it.
    private let dropLookback: TimeInterval = 1.5

    // Rep state machine
    /// The straightest and most bent the arm has been during the rep in progress.
    private var repTop: Double?
    private var repBottom: Double?
    /// A rep the elbow has finished, waiting on the shoulders to come back up.
    private struct PendingRep {
        let dropHigh: Double
        let dropTravel: Double
        let since: Date
    }
    private var pendingRep: PendingRep?
    /// Smoothed shoulder drop over the last `dropLookback`, so a rep's drop can be
    /// measured from just before its descent rather than from the last rep.
    private var recentDrops: [(at: Date, drop: Double)] = []

    // Arming
    /// Nothing counts until the user has been *still at the top* for a moment:
    /// arms near straight, shoulders not moving, for a full second.
    ///
    /// The earlier guard (a body tracked for 25 frames and 1.2 seconds, with a
    /// straight arm seen once) was satisfied within a second of the phone being
    /// propped up, five seconds before anyone had lain down. In one set it armed
    /// at 6.9s while the shoulders went on to travel 1.57 shoulder widths (three
    /// reps' worth) before the plank at 11.5s; the count survived only because
    /// the elbows happened never to bend more than 14 degrees on the way down.
    /// Anyone who bends an arm while lowering onto the floor gets charged for a
    /// rep they never did. The one thing setup never contains is stillness in a
    /// push-up top, so that is what arms the count.
    private var isArmed = false
    private var stillSince: Date?
    private var stillElbowLow = Double.infinity
    private var stillElbowHigh = -Double.infinity
    private var stillDropLow = Double.infinity
    private var stillDropHigh = -Double.infinity
    /// Between reps the same user rested at the top for 0.4-1.6s. A second is
    /// enough to fit the rest before a first rep and short enough that a set
    /// begun early arms at the next pause rather than never.
    private let armingStillness: TimeInterval = 1.0
    /// Rest tops in real footage read 155-180 degrees and drifted under 5 degrees
    /// frame to frame; the shoulders held to within 0.08 shoulder widths.
    private let restingElbow: Double = 150
    private let stillElbowRange: Double = 15
    /// Set on the capture queue when the tracked person changes, so the main
    /// actor can drop the arming that belonged to someone else.
    private var subjectSwitched = false

    /// Leg evidence gathered since the last rep, when the legs are in shot.
    ///
    /// Kept in two piles: everything, and only what was seen while the elbows
    /// were bent. The rep is judged on the second pile when it has enough in it,
    /// because the first includes the rest before the rep - and someone who
    /// sits back on their knees between reps, then straightens their legs to do
    /// one, has done a push-up. Judged on the whole window, the first rep of a
    /// real set was refused as kneeling on the strength of the two seconds of
    /// kneeling rest that preceded it. A cheat whose knees stay down through the
    /// rep is in both piles and is caught either way.
    private var repAnkleLifts: [Double] = []
    private var repKneeHeights: [Double] = []
    private var downAnkleLifts: [Double] = []
    private var downKneeHeights: [Double] = []
    /// Ankles above knees, in shoulder widths, past which the shins are folded
    /// up and this is a knee push-up.
    ///
    /// Measured off real footage rather than guessed: a plank read -0.02 and the
    /// same person kneeling read +0.15, so the line sits between them with room
    /// on both sides. The earlier attempt used the knee *angle*, which is noise
    /// from this camera position, and rejected perfect form.
    /// Set well past the kneeling reading rather than between the two, because
    /// the gate kept refusing honest push-ups on the phone even after both
    /// signals were made to agree. Everything between -0.02 and here now counts.
    private let kneelingLift: Double = 0.12
    /// Knees above the wrists, in shoulder widths, *below* which the knees are on
    /// the floor.
    ///
    /// The ankle test above needs ankles, and kneeling hides them: the shins lie
    /// flat pointing away from the lens and the feet sit behind the thighs. In a
    /// set of five knee push-ups the ankles were never seen once, and every cheat
    /// rep counted. The knees, though, still show at the bottom of the frame,
    /// and where they sit relative to the hands is the tell. Both are on the
    /// floor when kneeling, so the knees read level with or below the wrists
    /// (-0.26 to +0.13 in that footage); in a plank the knees are a foot off the
    /// floor and read 0.30-0.44 above them.
    ///
    /// The line used to sit between the two ranges, and that is what was refusing
    /// real reps. This measure is taken *against the wrists*, and on close grip
    /// the wrists disappear behind the head at the bottom of the rep - which is
    /// exactly when the leg samples are taken. A bad wrist read moves the
    /// reference rather than the knees, and the rep is thrown out for a cheat
    /// nobody committed. So the line now sits below the kneeling range's own
    /// middle: knees *underneath* the hands, which a plank cannot produce
    /// however badly the wrists are read.
    private let kneelingKneeHeight: Double = -0.05
    /// How many bottom-of-rep readings a leg measure needs before it is allowed an
    /// opinion, and how much of that pile has to agree with its own median.
    /// Both are high on purpose: this gate's failure mode is refusing real work.
    private let minimumLegSamples = 10
    private let legAgreement = 0.7
    /// True once legs have been seen at all. Without it there is no telling
    /// "kneeling" from "legs out of frame", and the second must never be punished
    /// as the first.
    private var hasSeenLegs = false

    /// Rejection messages have to outlive the frame that wrote them.
    ///
    /// Every frame used to end by setting `formHint`, so a "that one didn't count"
    /// written by a rejection was wiped about thirty milliseconds later and no
    /// user ever saw why a rep was refused. The counter looked broken because the
    /// one thing that would have explained it was invisible.
    private var hintExpiresAt: Date?
    private let hintDuration: TimeInterval = 2.5

    /// Shoulder width as a share of the frame, past which the body is too close
    /// for the arms to stay in shot at the bottom of a rep.
    private let tooCloseWidth: Double = 0.55
    private var isTooClose = false

    /// How much of the *smallest* countable travel counts as "started descending".
    ///
    /// Measured against the corroborated travel, not the solo one, and for a
    /// reason that cost a rep: a close-grip rep with 25 degrees of travel only
    /// crossed the old 24.5 degree entry line at its very bottom, so the rep was
    /// "entered" and "returned" within a couple of frames and thrown out as too
    /// fast. Entering earlier lets a shallow-reading rep be timed in full.
    private let descentEntry = 0.8
    /// How far back up the arm has to come for the rep to be complete, as a share
    /// of that rep's own excursion. Well short of the top, because most people
    /// never fully lock out between reps and waiting for it loses the rep.
    private let ascentReturn = 0.55
    private var rejections: [String: Int] = [:]
    private var isDown = false
    private var lastRepAt: Date = .distantPast
    private var missingBodyFrames = 0
    private var lastFrameAt: Date = .distantPast

    /// Thresholds sit inside the learned range rather than at its edges, so a rep
    /// doesn't have to hit the exact deepest point every single time.
    private let downThreshold = 0.62
    private let upThreshold = 0.38
    /// Vision joint confidence below this is treated as "not seeing you properly".
    /// Low on purpose: a half-seen elbow still tracks a rep, and demanding
    /// certainty is what drops frames mid-push-up.
    private let minimumConfidence: Float = 0.2
    /// Fast enough to resolve a quick rep, slow enough not to cook the phone.
    private let minimumFrameGap: TimeInterval = 1.0 / 30.0
    /// Nothing human produces two push-ups this close together.
    private let refractory: TimeInterval = 0.30

    init(exercise: Exercise, target: Int) {
        self.exercise = exercise
        self.target = target
        super.init()
    }

    // MARK: - Lifecycle

    @MainActor
    func start() async {
        startedAt = Date()
        phase = .counting
        jointMemory = [:]
        lastShoulderWidth = nil
        repTop = nil
        repBottom = nil
        rejections = [:]
        lockedSubjectCentre = nil
        hasSeenLegs = false
        clearLegSamples()
        hintExpiresAt = nil
        isTooClose = false
        disarm()

        // Everything but push-ups belongs to the sensor engine until it has a
        // joint model of its own. Failing loudly here is what routes it there.
        guard exercise == .pushUps else {
            tracking = .blocked("Rex can only watch push-ups for now.")
            return
        }
        guard await requestCameraAccess() else {
            tracking = .blocked("Rex needs the camera to count your reps.")
            return
        }
        guard configureSession() else {
            tracking = .blocked("No camera on this device, so Rex can't watch your form.")
            return
        }
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        tracking = .searching
    }

    @MainActor
    func stop() {
        stopSession()
        tracking = .idle
        if phase == .counting { phase = .finished }
    }

    /// Leaving the set entirely. Unlike `stop`, this never reports the set as
    /// finished, so an abandoned set can't be mistaken for a completed one.
    @MainActor
    func cancel() {
        stopSession()
        tracking = .idle
        phase = .idle
    }

    private func stopSession() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Returns false when the device has no usable front camera. The simulator is
    /// the common case: `AVCaptureDevice.default` hands back nil there, and without
    /// this the session runs with no input at all — a counter that looks live and
    /// silently never counts.
    @discardableResult
    private func configureSession() -> Bool {
        guard session.inputs.isEmpty else { return true }
        session.beginConfiguration()
        // Pose estimation doesn't need detail, but it does need enough pixels on a
        // body three feet away for the wrists to survive. `.medium` is the floor.
        session.sessionPreset = .hd1280x720

        var hasCamera = false
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            hasCamera = true
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            videoConnection = connection
            // Deliberately not mirrored: mirroring swaps Vision's left and right
            // joints, and the preview layer mirrors itself for the self-view.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        if let camera = activeCamera {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            rotationCoordinator = coordinator
            applyRotation()
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                self?.applyRotation()
            }
        }

        session.commitConfiguration()
        return hasCamera
    }

    private var activeCamera: AVCaptureDevice? {
        session.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first
    }

    private func applyRotation() {
        guard let coordinator = rotationCoordinator, let connection = videoConnection else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Exposed so the workout screen can show the user what the camera sees —
    /// people trust a counter far more when they can see it looking at them.
    var previewSession: AVCaptureSession { session }

    // MARK: - Measurement

    private typealias Joint = VNHumanBodyPoseObservation.JointName

    /// What one frame yielded. Both measurements are optional and independent:
    /// a frame that finds only the shoulders still moves the count along.
    private struct Reading {
        var elbow: Double?
        var drop: Double?
        /// How far the ankles sit above the knees, in shoulder widths. Kneeling
        /// folds the shins up and pushes this positive; a plank keeps it at or
        /// below zero. Nil means the legs aren't in shot, which is not the same
        /// as kneeling.
        var knee: Double?
        /// How far the knees sit above the wrists, in shoulder widths. Needs no
        /// ankles, which is the point: kneeling hides them. Nil when either the
        /// knees or the hands are out of shot.
        var kneeHeight: Double?
        var frame: PoseFrame
        var isUsable: Bool { elbow != nil || drop != nil }
    }

    /// The angle in degrees at `vertex`, between the limbs running to `a` and `b`.
    /// Scale- and position-invariant, which is the whole point: it reads the same
    /// whether the user is close to the phone or across the room.
    private func angle(_ a: CGPoint, _ vertex: CGPoint, _ b: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let dot = Double(v1.dx * v2.dx + v1.dy * v2.dy)
        let mag = Double(hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy))
        guard mag > 0 else { return 180 }
        return acos(max(-1, min(1, dot / mag))) * 180 / .pi
    }

    /// Picks which person in frame is the one doing the set.
    ///
    /// Vision hands back every body it finds, in no useful order, and taking the
    /// first one means a flatmate walking past the kitchen can steal the count
    /// mid-rep. The user is the one who set the phone up: nearest to it, and
    /// roughly in the middle of the shot. Nearness is read off apparent shoulder
    /// width, which is the cheapest proxy for distance a single camera has.
    ///
    /// Once chosen, the subject is sticky. Whoever was being counted a frame ago
    /// gets a large bonus, so a bystander who briefly looks bigger — leaning past
    /// the camera, say — can't take the set over.
    private func subject(from observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        guard observations.count > 1 else { return observations.first }

        var best: (observation: VNHumanBodyPoseObservation, centre: CGPoint, score: Double)?

        for observation in observations {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            let confident = points.values.filter { $0.confidence > minimumConfidence }
            guard confident.count >= 3 else { continue }

            let centre = CGPoint(
                x: confident.reduce(0) { $0 + $1.location.x } / CGFloat(confident.count),
                y: confident.reduce(0) { $0 + $1.location.y } / CGFloat(confident.count)
            )

            // Apparent size: shoulder span when both are visible, otherwise how
            // much of the frame the body's joints spread across.
            let scale: Double
            if let l = points[.leftShoulder], let r = points[.rightShoulder],
               l.confidence > minimumConfidence, r.confidence > minimumConfidence {
                scale = Double(hypot(l.location.x - r.location.x, l.location.y - r.location.y))
            } else {
                let ys = confident.map { $0.location.y }
                scale = Double((ys.max() ?? 0) - (ys.min() ?? 0)) * 0.4
            }

            let offCentre = Double(hypot(centre.x - 0.5, centre.y - 0.5))
            let centrality = 1 - min(1, offCentre / 0.7)

            var score = max(scale, 0.01) * (0.6 + 0.4 * centrality)
            if let locked = lockedSubjectCentre {
                let moved = Double(hypot(centre.x - locked.x, centre.y - locked.y))
                if moved < 0.25 { score *= 1.6 }
            }

            if score > (best?.score ?? -1) {
                best = (observation, centre, score)
            }
        }

        guard let best else { return observations.first }

        // A genuine switch of subject invalidates everything remembered about the
        // old one — held joints and shoulder width both belong to a body that is
        // no longer the one being counted.
        if let locked = lockedSubjectCentre,
           Double(hypot(best.centre.x - locked.x, best.centre.y - locked.y)) > 0.35 {
            jointMemory = [:]
            lastShoulderWidth = nil
            subjectSwitched = true
        }
        lockedSubjectCentre = best.centre
        return best.observation
    }

    private func read(_ observation: VNHumanBodyPoseObservation, now: Date) -> Reading? {
        let recognized = (try? observation.recognizedPoints(.all)) ?? [:]

        // Wrists and elbows are the hardest joints to see and the ones the whole
        // measurement depends on, so they're read at a lower bar than the
        // shoulders that anchor it.
        func threshold(for joint: Joint) -> Float {
            switch joint {
            case .leftWrist, .rightWrist, .leftElbow, .rightElbow: return 0.15
            default: return minimumConfidence
            }
        }

        func raw(_ joint: Joint) -> CGPoint? {
            if let p = recognized[joint], p.confidence > threshold(for: joint) {
                jointMemory[joint] = (p.location, now)
                return p.location
            }
            guard let last = jointMemory[joint],
                  now.timeIntervalSince(last.at) <= jointHold else { return nil }
            return last.point
        }

        /// Aspect-corrected, for measuring. Vision normalises into a unit square,
        /// so on a 16:9 frame the x axis is compressed and any angle or distance
        /// read straight off those coordinates is skewed.
        func measured(_ joint: Joint) -> CGPoint? {
            guard let p = raw(joint) else { return nil }
            return CGPoint(x: p.x * frameAspect, y: p.y)
        }

        // --- Elbow angle, averaged across whichever arms are fully visible ---
        func arm(_ shoulder: Joint, _ elbow: Joint, _ wrist: Joint) -> Double? {
            guard let s = measured(shoulder), let e = measured(elbow), let w = measured(wrist) else { return nil }
            return angle(s, e, w)
        }
        let arms = [arm(.leftShoulder, .leftElbow, .leftWrist),
                    arm(.rightShoulder, .rightElbow, .rightWrist)].compactMap { $0 }
        let elbow = arms.isEmpty ? nil : arms.reduce(0, +) / Double(arms.count)

        // --- Shoulder height, in shoulder-widths ---
        //
        // Measuring the drop against the user's own shoulder width is what makes
        // it survive them being closer to the phone than last time: both scale
        // together, so the ratio doesn't care about distance.
        var drop: Double?
        let leftShoulder = measured(.leftShoulder)
        let rightShoulder = measured(.rightShoulder)

        var width = lastShoulderWidth
        if let l = leftShoulder, let r = rightShoulder {
            let seen = Double(hypot(l.x - r.x, l.y - r.y))
            if seen > 0.02 {
                width = seen
                lastShoulderWidth = seen
                // Shoulders filling the frame means the arms leave it at the
                // bottom of every rep, which reads as reps that simply vanish.
                isTooClose = seen > tooCloseWidth
            }
        }

        // One shoulder plus a remembered width still measures height perfectly
        // well, which is what keeps this alive when a head crosses the chest.
        let heights = [leftShoulder?.y, rightShoulder?.y].compactMap { $0 }
        if let width, width > 0.02, !heights.isEmpty {
            // Vision's origin is bottom-left, so subtracting from 1 makes a
            // bigger number mean lower in frame, i.e. deeper into the push-up.
            let midY = 1 - Double(heights.reduce(0, +)) / Double(heights.count)
            drop = midY / width
        }

        // --- Legs ---
        //
        // The knee *angle* cannot be used from this camera position, which is what
        // made the first attempt reject perfect form. Filmed head-on, a plank's
        // legs point straight away from the lens, so hip, knee and ankle project
        // to nearly the same spot on the image and the angle between them is
        // computed from noise. It read as "bent" for people whose legs were
        // perfectly straight, and read fine for people kneeling.
        //
        // Height survives the projection where angle doesn't. Kneeling folds the
        // shins upward, so the ankles sit *above* the knees in frame; in a plank
        // the feet are on the floor, at or below knee level. Measured in shoulder
        // widths so it doesn't care how far away the body is.
        var ankleLift: Double?
        var kneeHeight: Double?
        if let width = lastShoulderWidth, width > 0.02 {
            let knees = [measured(.leftKnee)?.y, measured(.rightKnee)?.y].compactMap { $0 }
            let ankles = [measured(.leftAnkle)?.y, measured(.rightAnkle)?.y].compactMap { $0 }
            let wrists = [measured(.leftWrist)?.y, measured(.rightWrist)?.y].compactMap { $0 }
            if !knees.isEmpty {
                let kneeY = Double(knees.reduce(0, +)) / Double(knees.count)
                // Vision's origin is bottom-left, so a larger y is higher up.
                if !ankles.isEmpty {
                    let ankleY = Double(ankles.reduce(0, +)) / Double(ankles.count)
                    ankleLift = (ankleY - kneeY) / width
                }
                // The wrists are on the floor for the whole rep, which makes them
                // the one fixed reference the frame has for "floor level" - and
                // a knee at floor level is a knee that is kneeling.
                if !wrists.isEmpty {
                    let wristY = Double(wrists.reduce(0, +)) / Double(wrists.count)
                    kneeHeight = (kneeY - wristY) / width
                }
            }
        }

        // --- Joints to draw ---
        var joints: [PoseFrame.Joint: CGPoint] = [:]
        for (key, name) in PoseFrame.visionJoints {
            if let p = raw(name) { joints[key] = CGPoint(x: p.x, y: 1 - p.y) }
        }

        let reading = Reading(elbow: elbow, drop: drop, knee: ankleLift, kneeHeight: kneeHeight,
                              frame: PoseFrame(joints: joints, aspect: frameAspect))
        return reading.isUsable ? reading : nil
    }

    /// Rep state machine. Fuses whichever signals this frame produced into one
    /// depth, then looks for a crossing down and back up.
    @MainActor
    private func consume(_ reading: Reading) {
        // The tracks still smooth, and still feed the diagnostics. They no longer
        // decide anything: counting is done against each rep's own peak and
        // valley, below.
        _ = reading.elbow.map { elbowTrack.push($0) }
        _ = reading.drop.map { dropTrack.push($0) }
        let elbow = reading.elbow != nil ? elbowTrack.current : nil
        let drop = reading.drop != nil ? dropTrack.current : nil

        repWindow.observe(elbow: elbow, drop: drop)
        if let drop {
            let now = Date()
            recentDrops.append((now, drop))
            recentDrops.removeAll { now.timeIntervalSince($0.at) > dropLookback }
        }
        if let knee = reading.knee {
            hasSeenLegs = true
            repAnkleLifts.append(knee)
            if isDown { downAnkleLifts.append(knee) }
        }
        if let kneeHeight = reading.kneeHeight {
            hasSeenLegs = true
            repKneeHeights.append(kneeHeight)
            if isDown { downKneeHeights.append(kneeHeight) }
        }
        if let pending = pendingRep {
            settle(pending, dropNow: drop)
        }

        #if DEBUG
        diagnostics = String(
            format: "e %@ · top %@ btm %@ · drop %@ · lift %@ · knee %@ · %@%@",
            elbow.map { String(format: "%.0f°", $0) } ?? "-",
            repTop.map { String(format: "%.0f", $0) } ?? "-",
            repBottom.map { String(format: "%.0f", $0) } ?? "-",
            repWindow.dropTravel.map { String(format: "%.2f", $0) } ?? "-",
            repAnkleLifts.last.map { String(format: "%+.2f", $0) } ?? "-",
            repKneeHeights.last.map { String(format: "%+.2f", $0) } ?? "-",
            isArmed ? (pendingRep != nil ? "wait" : "armed") : "hold",
            rejectionSummary
        )
        #endif

        guard let elbow else {
            formHint = "Rex needs to see your elbows. Get your hands in frame."
            return
        }

        if !isArmed {
            updateArming(elbow: elbow, drop: drop)
        }
        let state: Tracking = isArmed ? .tracking : .calibrating
        if tracking != state { tracking = state }

        // Each rep is measured against its own top and bottom rather than against
        // a range learned across the set.
        //
        // A rolling range can only describe the *average* rep, so anything that
        // isn't average falls outside it: the shallower reps at the end of a set
        // never reach the threshold, and a fast rep gets flattened by smoothing
        // until its peak lands short of one. Turning points don't have that
        // problem — a small fast rep has the same shape as a big slow one, and
        // the absolute gates below are what keep a *shrug* from being a rep.
        if !isDown {
            repTop = max(repTop ?? elbow, elbow)
            repBottom = elbow
            if isArmed, let top = repTop, top - elbow >= corroboratedElbowTravel * descentEntry {
                isDown = true
                repWindow.startedDownAt = .now
                repWindow.rescopeDrop(to: recentDrops.map(\.drop))
                // Descending again with the last rep still waiting on the
                // shoulders means they never came back up, so it wasn't a rep.
                if let pending = pendingRep {
                    pendingRep = nil
                    refuseReturn(pending)
                }
            }
        } else {
            repBottom = min(repBottom ?? elbow, elbow)
            if let top = repTop, let bottom = repBottom {
                let excursion = top - bottom
                if excursion > 0, elbow >= bottom + excursion * ascentReturn {
                    isDown = false
                    judgeRep(top: top, bottom: bottom, dropNow: drop)
                    // Carry the top forward rather than reseeding it from wherever
                    // the arm happens to be. Someone tiring stops locking out, so a
                    // top taken from the last rep's end creeps down until the travel
                    // gate starts eating honest reps - which is what turned fifteen
                    // push-ups into ten.
                    repTop = max(elbow, top - 15)
                    repBottom = elbow
                }
            }
        }

        if let top = repTop, let bottom = repBottom {
            depth = max(0, min(1, (top - elbow) / max(minElbowTravel, top - bottom)))
        }
        // A rejection has the floor until it times out. Anything else here would
        // wipe it before it could be read.
        if let expiry = hintExpiresAt, expiry > Date() { return }
        hintExpiresAt = nil

        if isTooClose {
            formHint = "You're a little close - back up so your arms stay in shot."
        } else if !hasSeenLegs, reps == 0 {
            // Said once, gently: with the legs out of shot the count still works,
            // it just can't tell a push-up from a knee push-up.
            formHint = "Step back if you can - Rex counts best with your legs in shot."
        } else {
            formHint = nil
        }
    }

    /// Decides whether the movement just completed was a push-up.
    ///
    /// Corroboration is the rule: when the shoulders were visible too, they have
    /// to agree. A genuine push-up bends the elbows *and* drops the shoulders, so
    /// requiring both is what separates it from the two easy fakes — bobbing the
    /// shoulders with locked arms, and flapping the elbows without lowering the
    /// chest. The elbows are never optional, in either direction: a downward dog
    /// drops the shoulders through a huge range on straight arms, and any check
    /// that lets shoulder travel vote alone counts that as a set.
    @MainActor
    private func judgeRep(top: Double, bottom: Double, dropNow: Double?) {
        defer {
            repWindow = RepWindow()
            clearLegSamples()
        }
        let duration = repWindow.startedDownAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let brief = duration < briefExcursion

        // Knees down is the one cheat the arms cannot give away: the elbows do
        // identical work either way. It is only catchable with the legs in shot,
        // so a rep with no legs visible is counted rather than doubted - the
        // alternative punishes a badly framed camera as though it were dishonesty.
        // The median, so one frame of a shin crossing the other can't cost a rep.
        // Only judged when the legs were actually in shot for a good part of the
        // rep - out of frame is not the same as kneeling, and must never be
        // punished as though it were.
        //
        // Two independent tells, either of which is enough. The ankle test is the
        // original; the knee-height test exists because kneeling hides the
        // ankles, and a cheat that hides the only evidence against it is not a
        // cheat that gets caught.
        // Kneeling has to be obvious, sustained, and read from the bottom of the
        // rep before it costs anybody a rep.
        //
        // The first version of this gate fired on a single measure crossing a line
        // drawn midway between the two ranges, and it refused honest push-ups over
        // and over on a real phone. Both thresholds have since been pushed out past
        // the kneeling readings themselves, and a rejection now needs a decent pile
        // of samples taken while the elbows were bent, a median past the line, and
        // most of those samples agreeing with the median. Scattered noise from
        // legs at the edge of the frame can no longer refuse a rep on its own.
        //
        // This deliberately lets a marginal knee push-up through. That costs a few
        // minutes. Refusing work somebody actually did costs their belief in the
        // counter, and there is nothing they can do to argue with it.
        let anklesSayKneeling = kneelingVerdict(downAnkleLifts, says: { $0 > kneelingLift })
        let kneesSayKneeling = kneelingVerdict(downKneeHeights, says: { $0 < kneelingKneeHeight })
        if anklesSayKneeling || kneesSayKneeling {
            reject("knees", "Knees are down - straighten your legs to count.")
            return
        }

        if duration < minimumRepDuration {
            reject("fast", "Too fast to read - lower under control.", quietly: true)
            return
        }

        let drop = repWindow.dropTravel
        let travel = top - bottom

        // A strong shoulder drop, seen for the whole rep, vouches for the elbow
        // and relaxes its gates. Without it the elbow stands alone and has to
        // prove the rep by itself.
        let corroborated = drop.map { $0 >= strongDropTravel } == true && repWindow.sawShouldersThroughout
        let requiredTravel = corroborated ? corroboratedElbowTravel
            : drop == nil ? soloElbowTravel : minElbowTravel
        let allowedBottom = corroborated ? corroboratedBottomAngle : maxBottomAngle

        guard travel >= requiredTravel else {
            reject("travel", "Not deep enough - bend your elbows further.", quietly: brief)
            return
        }
        guard bottom <= allowedBottom else {
            reject("locked", "Arms stayed straight - bend them to count.", quietly: brief)
            return
        }
        // The chest has to come down, which is the second of the two things a
        // push-up actually is. Only judged when the shoulders were visible for
        // most of the rep, and at a threshold well under a real rep's travel, so a
        // blink in tracking can't refuse honest work.
        if let drop, repWindow.sawShouldersThroughout, drop < minDropTravel {
            reject("chest", "Chest didn't drop - lower all the way down.")
            return
        }
        // And the chest has to come back. Shoulders that are still at their
        // lowest when the elbows have straightened were not doing a push-up; they
        // were arriving somewhere - typically the floor, at the start of a set.
        // Or the elbow reading ran ahead of the body, which is why the rep waits
        // rather than being refused on the spot.
        if let drop, repWindow.sawShouldersThroughout, drop >= minDropTravel {
            let pending = PendingRep(dropHigh: repWindow.dropHigh, dropTravel: drop, since: .now)
            if hasReturned(pending, dropNow: dropNow) {
                commitRep()
            } else {
                pendingRep = pending
            }
            return
        }

        commitRep()
    }

    private func hasReturned(_ pending: PendingRep, dropNow: Double?) -> Bool {
        guard let dropNow else { return false }
        return pending.dropHigh - dropNow >= pending.dropTravel * minimumShoulderReturn
    }

    /// Banks a waiting rep the moment the shoulders are back, or refuses it once
    /// they have had long enough and haven't come.
    @MainActor
    private func settle(_ pending: PendingRep, dropNow: Double?) {
        if hasReturned(pending, dropNow: dropNow) {
            pendingRep = nil
            commitRep()
        } else if Date().timeIntervalSince(pending.since) > shoulderReturnTimeout {
            pendingRep = nil
            refuseReturn(pending)
        }
    }

    @MainActor
    private func refuseReturn(_ pending: PendingRep) {
        reject("return", "Push all the way back up to count.")
    }

    private func clearLegSamples() {
        repAnkleLifts = []
        repKneeHeights = []
        downAnkleLifts = []
        downKneeHeights = []
    }

    /// Nil until there are enough samples for the middle one to mean anything -
    /// five, so that a couple of frames of a shin glimpsed mid-rep decide nothing.
    private func median(of samples: [Double]) -> Double? {
        guard samples.count >= 5 else { return nil }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Whether a leg measure says "kneeling" convincingly enough to refuse a rep.
    ///
    /// Three hurdles, all of which exist because a single crossing of a single
    /// line was refusing real push-ups: enough samples that this is not one bad
    /// frame, a median past the line rather than any reading past it, and most of
    /// the samples agreeing with that median. Fewer than `minimumLegSamples`
    /// readings is not evidence of anything and the rep is allowed - a camera that
    /// cannot see your legs must never be treated as a camera catching you.
    private func kneelingVerdict(_ samples: [Double],
                                 says isKneeling: (Double) -> Bool) -> Bool {
        guard samples.count >= minimumLegSamples,
              let middle = median(of: samples), isKneeling(middle) else { return false }
        let agreeing = samples.filter(isKneeling).count
        return Double(agreeing) / Double(samples.count) >= legAgreement
    }

    // MARK: - Arming

    /// Feeds one frame into the stillness check and arms the count once the user
    /// has held a push-up top for `armingStillness`. Any frame that isn't a
    /// still top - arms bent, shoulders moving, shoulders unseen - starts the
    /// clock again.
    @MainActor
    private func updateArming(elbow: Double, drop: Double?) {
        let now = Date()
        guard let drop, elbow >= restingElbow else {
            resetStillness()
            return
        }
        stillElbowLow = min(stillElbowLow, elbow)
        stillElbowHigh = max(stillElbowHigh, elbow)
        stillDropLow = min(stillDropLow, drop)
        stillDropHigh = max(stillDropHigh, drop)
        if stillElbowHigh - stillElbowLow > stillElbowRange || stillDropHigh - stillDropLow > minDropTravel {
            // Restart from this frame rather than from nothing, so a single
            // outlier costs one second and not two.
            resetStillness()
            stillElbowLow = elbow; stillElbowHigh = elbow
            stillDropLow = drop; stillDropHigh = drop
        }
        if stillSince == nil { stillSince = now }
        guard let since = stillSince, now.timeIntervalSince(since) >= armingStillness else { return }

        isArmed = true
        // Everything gathered while the user was getting into position belongs to
        // the setup, not to the first rep: shoulders travelling to the floor
        // would read as a huge drop, and legs seen kneeling on the way down would
        // convict an honest first rep.
        repWindow = RepWindow()
        clearLegSamples()
        repTop = elbow
        repBottom = elbow
        isDown = false
    }

    private func resetStillness() {
        stillSince = nil
        stillElbowLow = .infinity
        stillElbowHigh = -.infinity
        stillDropLow = .infinity
        stillDropHigh = -.infinity
    }

    /// Back to needing a still top. Called when the body is lost or replaced: a
    /// user who has walked off and come back is setting up again, with all the
    /// stray movement that entails.
    private func disarm() {
        isArmed = false
        isDown = false
        repTop = nil
        repBottom = nil
        pendingRep = nil
        recentDrops = []
        resetStillness()
    }

    /// Seen, judged, and not counted. Saying so is the difference between a
    /// counter that feels strict and one that feels broken; tallying it by reason
    /// is what makes the next round of tuning arithmetic instead of guesswork.
    ///
    /// `quietly` still tallies the refusal for the diagnostics but tells the user
    /// nothing: it is for excursions too brief to have been an attempt, where a
    /// buzz and a correction would be scolding someone for standing still.
    @MainActor
    private func reject(_ reason: String, _ message: String, quietly: Bool = false) {
        rejectedReps += 1
        rejections[reason, default: 0] += 1
        guard !quietly else { return }
        formHint = message
        hintExpiresAt = Date().addingTimeInterval(hintDuration)
        Haptics.warning()
    }

    private var rejectionSummary: String {
        guard !rejections.isEmpty else { return "" }
        return " · x " + rejections.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
    }

    @MainActor
    private func commitRep() {
        guard Date().timeIntervalSince(lastRepAt) > refractory else {
            rejectedReps += 1
            return
        }
        lastRepAt = .now
        reps += 1
        Haptics.rep()
        if reps >= target { stop() }
    }
}

// MARK: - Adaptive range

/// One measured quantity, smoothed and normalised against the range the user has
/// actually been moving through for the last few seconds.
///
/// The range comes from **percentiles of a rolling window**, not from the largest
/// and smallest values ever seen. That distinction is the difference between a
/// counter that works and one that goes quiet: an all-time envelope only ever
/// widens, so a single bad frame — one elbow briefly mis-detected as straight —
/// stretches it permanently, and every honest rep afterwards covers too little of
/// it to cross a threshold.
private struct SignalTrack {
    /// How much of the range must be covered before the signal means anything.
    /// Below it the user is holding still and the spread is just noise.
    let minimumSpan: Double
    let smoothing: Double
    /// Six seconds at 20fps — long enough to hold a couple of reps, short enough
    /// to follow someone whose form drifts as they tire.
    private let capacity = 120

    private var samples: [Double] = []
    /// The smoothed raw measurement — degrees, or shoulder-widths. The normalised
    /// value says *where in your range* you are; this says how far you actually
    /// moved, which is the only thing a rep can honestly be judged on.
    private(set) var current: Double?
    private var smoothed: Double?

    init(minimumSpan: Double, smoothing: Double) {
        self.minimumSpan = minimumSpan
        self.smoothing = smoothing
    }

    var span: Double {
        guard let low = percentile(0.1), let high = percentile(0.9) else { return 0 }
        return high - low
    }

    /// Feeds in a raw sample and returns where it sits in the learned range, 0-1,
    /// or nil while the range is too narrow to be meaningful.
    mutating func push(_ raw: Double) -> Double? {
        let value = smoothed.map { $0 + (raw - $0) * smoothing } ?? raw
        smoothed = value
        current = value

        samples.append(value)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }

        guard samples.count >= 20,
              let low = percentile(0.1),
              let high = percentile(0.9),
              high - low >= minimumSpan
        else { return nil }

        return max(0, min(1, (value - low) / (high - low)))
    }

    private func percentile(_ q: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * q).rounded())
        return sorted[index]
    }
}

// MARK: - Frame handling

extension PoseRepCounter: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameAt) >= minimumFrameGap else { return }
        lastFrameAt = now

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let height = CVPixelBufferGetHeight(buffer)
        if height > 0 { frameAspect = Double(CVPixelBufferGetWidth(buffer)) / Double(height) }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                            orientation: visionOrientation,
                                            options: [:])
        try? handler.perform([poseRequest])

        guard let observation = subject(from: poseRequest.results ?? []),
              let reading = read(observation, now: now) else {
            missingBodyFrames += 1
            guard missingBodyFrames > 25 else { return }
            Task { @MainActor in
                guard self.phase == .counting else { return }
                self.tracking = .searching
                self.poseFrame = nil
                self.formHint = "Stand the phone up facing you, past your hands."
                self.disarm()
            }
            return
        }

        missingBodyFrames = 0
        let switched = subjectSwitched
        subjectSwitched = false

        Task { @MainActor in
            guard self.phase == .counting else { return }
            if switched { self.disarm() }
            self.poseFrame = reading.frame
            self.consume(reading)
        }
    }
}

/// One frame of arm geometry, normalised with a top-left origin, ready to draw
/// over the preview.
struct PoseFrame: Equatable {
    enum Joint: String, CaseIterable {
        case leftShoulder, rightShoulder
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
    }

    var joints: [Joint: CGPoint]
    /// Width / height of the video underneath, so the overlay can reproduce the
    /// preview layer's aspect-fill crop exactly and land on the body.
    var aspect: Double

    /// The whole body, not just the arms.
    ///
    /// Drawing the legs is not decoration: it is the only way a user can see
    /// whether the app can see their legs, and the legs are what tell a push-up
    /// from a knee push-up. Bones whose joints aren't visible simply don't draw,
    /// so a half-framed body renders as much of itself as the camera has.
    static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    static let visionJoints: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]
}
