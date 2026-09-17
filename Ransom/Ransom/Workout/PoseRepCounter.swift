// AVCaptureSession is not Sendable, but it is documented as safe to drive from
// one serial queue, which is exactly what `queue` is and the only place the
// session is ever started or stopped.
@preconcurrency import AVFoundation
import CoreMotion
import Foundation
import Observation
import UIKit
import Vision

/// Counts push-ups and squats by watching the body, not the phone.
///
/// The sensor detectors this replaces are all trivially cheatable — a hand waved
/// over the proximity sensor is a push-up, a shaken phone is ten jumping jacks.
/// That matters more than it sounds: if the count can be faked then the lifetime
/// figure, the streak and the whole ledger are decorative, and a user who works
/// that out has no reason left to open the app.
///
/// **Two movements, one counter.** A rep has the same shape whichever movement it
/// is: a body-internal measure that falls on the way down and comes back (an
/// elbow angle, a thigh pitch) and a frame-position measure that has to agree
/// with it (shoulders dropping, hips dropping). Everything that acts on that
/// shape is written once. What differs - which joints, how far, what to say -
/// lives in `Movement`, and nowhere else. Steps fall straight through to
/// `RepEngine`: there is no body movement to watch.
///
/// Runs Vision's body-pose request on the front camera, entirely on device. No
/// frame is written to disk, uploaded, or kept beyond the moment it's measured.
///
/// Four things make this work where a naive implementation misses half the set:
///
///  1. **Framing the model can read.** For push-ups the phone stands vertically
///     facing the user, past their hands: head-on a push-up reads as an upright
///     body — head at the top, hands at the bottom — where filmed from the side
///     the same body lies flat across the frame, the pose the model is worst at.
///     For squats the phone stands a few feet away facing the user, so the whole
///     body is in shot, upright and frontal, which is the pose the model is best
///     at. The body is far smaller in frame, and that is the trade: every joint
///     is visible, none of them is seen closely.
///  2. **One signal decides, one corroborates.** The body-internal measure is the
///     only one that means "push-up" or "squat" — so no rep is banked without it,
///     however convincing the rest of the body looks. The frame-position measure
///     is tracked alongside it and has to agree, but it can never carry a rep
///     alone: a downward dog drops the shoulders through a huge range on locked
///     arms, and a step backwards from a floor-level phone drops the hips through
///     a huge range on straight legs. Any check that lets the frame-position
///     signal vote by itself counts those as sets.
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
///     movement — degrees of elbow bend, or hips-above-knees and hip height in
///     shoulder-widths — all of which have to clear a fixed bar before a rep is
///     banked.
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

    /// Why nothing is being counted, as a state rather than a sentence.
    ///
    /// The sentences still exist and still explain themselves, but a sentence is
    /// not what somebody face down on the floor can read. Each of these carries
    /// two or three words the screen can shout instead, with the explanation
    /// underneath it in the size prose belongs in.
    enum Blocker: Equatable {
        /// Close enough that the joints leave the frame at the bottom of a rep.
        case tooClose
        /// A body is in shot, but the joints this movement is measured on aren't.
        case bodyNotInShot
        /// No usable body in frame at all.
        case noBody
        /// The phone is lying back far enough to be watching the ceiling. Named
        /// after the fix rather than the fault: "flat" describes what a sensor
        /// noticed, and nobody reading it mid-set has to care about that.
        case phoneTilted

        /// Short enough to read at a glance, from the floor, mid-rep.
        var shout: String {
            switch self {
            case .tooClose:      return "BACK UP"
            case .bodyNotInShot: return "MOVE INTO SHOT"
            case .noBody:        return "CAN'T SEE YOU"
            case .phoneTilted:   return "PROP THE PHONE UP"
            }
        }

        /// Used only when the detector has no more specific sentence of its own.
        var detail: String {
            switch self {
            case .tooClose:      return "Back up a little bit before continuing."
            case .bodyNotInShot: return "Shift until Rex can see all of you."
            case .noBody:        return "Step in front of the phone."
            case .phoneTilted:   return "Lean it against a wall so it faces you."
            }
        }
    }

    private(set) var reps = 0
    private(set) var phase: Phase = .idle
    private(set) var tracking: Tracking = .idle
    /// 0 = top of the rep, 1 = bottom. Drives Rex, same as the sensor path did.
    private(set) var depth: Double = 0
    /// Nil when form is fine; otherwise one short correction.
    private(set) var formHint: String?
    /// Nil when nothing is in the way. Whatever this holds, the screen shouts.
    private(set) var blocker: Blocker?
    /// Bounces rejected as too fast to be real. Kept so the count can be defended.
    private(set) var rejectedReps = 0
    /// The body as last seen, for the skeleton drawn over the preview. Seeing the
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

    /// Which joints to read, how far they have to move, and what to say when
    /// they don't. Chosen once from `exercise`; see `Movement` for why the split
    /// falls exactly there.
    private let movement: Movement

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
    ///
    /// Squats have their own version of the same blink: arms that hang at the
    /// sides swing in front of the hips at the bottom of the rep, which is where
    /// the hip joint matters most. Same hold, same reason.
    private let jointHold: TimeInterval = 0.7
    /// Shoulder width is the yardstick the height signals are measured in, and it
    /// barely changes during a set — so once seen it's remembered, and a single
    /// visible shoulder is enough to keep measuring.
    private var lastShoulderWidth: Double?
    /// The shoulder width at the top of the rep, which is the yardstick the
    /// height signal is actually measured in once the count is armed.
    ///
    /// Measuring the drop in *current* shoulder widths was the bug that made the
    /// height signal unreadable head on. The shoulders come towards a floor
    /// level phone on the way down, and the elbows flare, so the apparent
    /// shoulder width grows 10-30% at the bottom of every rep (read off four
    /// screen recordings: 157 to 215 px, 117 to 143, 182 to 258, 136 to 194).
    /// Dividing a modest height change by a yardstick that is swelling at the
    /// same time shrinks the ratio, and for a second person doing knee push-ups
    /// with a low camera it reversed it outright: every one of her ten reps read
    /// -0.15 to -0.57 "drop", so the shoulders appeared to *rise* at the bottom.
    /// Nine of those reps still counted, by accident of the ordering; the tenth
    /// was refused with "Push all the way back up" while she was visibly back at
    /// the top, because a reversed signal can never satisfy a return check. The
    /// same reps measured against the width seen at the top read +0.38 to +1.27,
    /// every one of them positive, and every one clear of `strongDropTravel`.
    ///
    /// So the yardstick is frozen at the moment the count arms - the user has
    /// just held the top still for a second, so it is a clean top width - and
    /// then only nudged, slowly, while the arms are straight again between reps,
    /// so someone who shuffles closer to the phone mid set is re-measured within
    /// a couple of seconds. It is never touched during a descent, which is the
    /// whole point. Nil until armed, and cleared with everything else on disarm;
    /// before arming the current width is used, exactly as before, so the
    /// stillness check sees no step when the freeze happens.
    private var restingShoulderWidth: Double?
    /// How fast the resting width follows the top-of-rep width, per frame.
    /// About two seconds to settle at 30fps: slow enough that a few frames of an
    /// elbow reading "straight" while the shoulders are still low (which head-on
    /// footage does produce) move it by well under a percent.
    private let restingWidthFollow = 0.03
    /// Hands-to-feet horizontal distance in shoulder widths, this frame. Large
    /// means the camera is seeing the body side on; small means it is pointed
    /// down the length of it and the legs are a smudge.
    private var bodySpread: Double?
    /// Spread values gathered during the rep, so the framing is judged over the
    /// whole movement rather than off one frame at the bottom.
    private var repSpreads: [Double] = []
    /// Where the person being counted was last seen, so the count stays with them
    /// when someone else walks into shot.
    private var lockedSubjectCentre: CGPoint?

    /// Width / height of the frames being delivered. Vision reports joints in a
    /// normalised unit square, so on a non-square frame the x axis is compressed
    /// relative to y and any angle measured in those coordinates is skewed.
    private var frameAspect: Double = 1

    // MARK: Signal conditioning

    /// The movement's own measure: elbow angle in degrees for push-ups, hips
    /// above knees in shoulder widths for squats. Falls on the way down and
    /// comes back up in both cases, which is what lets one state machine time
    /// both. The truest signal, when its joints are visible.
    private var primaryTrack: SignalTrack
    /// Height in frame, in shoulder-widths: the shoulders for push-ups, the hips
    /// for squats. Rises as the body drops. Needs only two joints Vision is
    /// confident about, so it keeps counting through everything that hides the
    /// wrists or the knees.
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
        var primaryLow = Double.infinity
        var primaryHigh = -Double.infinity
        var dropLow = Double.infinity
        var dropHigh = -Double.infinity
        var primaryFrames = 0
        var dropFrames = 0
        var totalFrames = 0
        var startedDownAt: Date?

        mutating func observe(primary: Double?, drop: Double?) {
            totalFrames += 1
            if let primary {
                primaryFrames += 1
                primaryLow = min(primaryLow, primary)
                primaryHigh = max(primaryHigh, primary)
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

        var primaryTravel: Double? {
            guard sawEnough(primaryFrames), primaryHigh > primaryLow else { return nil }
            return primaryHigh - primaryLow
        }

        var dropTravel: Double? {
            guard sawEnough(dropFrames), dropHigh > dropLow else { return nil }
            return dropHigh - dropLow
        }

        /// The height signal tracked for most of the rep, not merely glimpsed.
        /// Only then is a small drop evidence of a shallow rep rather than of a
        /// blink.
        var sawDropThroughout: Bool {
            totalFrames > 0 && Double(dropFrames) / Double(totalFrames) >= 0.7
        }

        /// The lowest the primary signal got. Travel alone can be produced by a
        /// body that starts already folded; this insists it reached a real
        /// bottom position.
        var primaryBottom: Double? {
            guard sawEnough(primaryFrames), primaryLow.isFinite else { return nil }
            return primaryLow
        }

        /// Forgets the height extremes gathered during the rest and restarts
        /// them from the moments just before the descent. The rest is where the
        /// user shifts, looks up, or sits back, none of which is a rep, and all
        /// of which read as a huge drop if left in.
        ///
        /// The top comes from a longer window than the bottom. See
        /// `dropLeadLookback` for the reach that this told apart from a rep.
        mutating func rescopeDrop(topFrom recent: [Double], bottomFrom lead: [Double]) {
            dropLow = recent.min() ?? .infinity
            dropHigh = lead.max() ?? -.infinity
        }
    }

    private var repWindow = RepWindow()

    /// Nobody descends and returns in under a third of a second.
    private let minimumRepDuration: TimeInterval = 0.18
    /// How far back up the height signal must come, as a share of the rep's own
    /// drop, before a rep the primary signal has finished is banked.
    ///
    /// This is what tells a push-up from *getting into position*. Lowering
    /// oneself from kneeling into a plank bends and straightens the elbows just
    /// like a rep, but the shoulders finish at the bottom of their travel and
    /// stay there. A rep brings them back. The squat equivalent is sitting down
    /// on a chair: the thighs pitch to parallel exactly as a squat does, and the
    /// hips stay there.
    private let minimumShoulderReturn = 0.25
    /// How long a finished rep waits for the height signal to come back before
    /// it is refused.
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
    /// How far back before the primary signal starts to fall the height signal
    /// is measured from. In close grip the shoulders lead the elbow reading by up
    /// to 0.6s; anything older than this is the rest between reps, and a rest is
    /// where the user shifts about. Measured over a whole rest the "drop" reached
    /// 2.0 shoulder widths without a single rep in it.
    ///
    /// This window seeds only the *top* of the rep's height range. The bottom
    /// is seeded from the shorter `dropLeadLookback`, because 1.5s reaches back
    /// into the previous rep's ascent when reps come close together: a one-armed
    /// reach for the phone 1.2s after a rep bent one elbow 29 degrees, moved the
    /// shoulders 0.24 of their own accord, and was "corroborated" to 0.6 by the
    /// bottom of the rep before it. The shoulders can be partway down before the
    /// elbow reading moves - that is what the lookback is for - but they cannot
    /// have reached the bottom of a rep that hasn't started.
    private let dropLookback: TimeInterval = 1.5
    private let dropLeadLookback: TimeInterval = 0.6

    // Rep state machine
    /// The highest and lowest the primary signal has been during the rep in
    /// progress: straightest and most bent arm, tallest and lowest thigh.
    private var repTop: Double?
    private var repBottom: Double?
    /// A rep the primary signal has finished, waiting on the height signal to
    /// come back up.
    private struct PendingRep {
        let dropHigh: Double
        let dropTravel: Double
        let since: Date
    }
    private var pendingRep: PendingRep?
    /// Smoothed height signal over the last `dropLookback`, so a rep's drop can
    /// be measured from just before its descent rather than from the last rep.
    private var recentDrops: [(at: Date, drop: Double)] = []

    // Arming
    /// Nothing counts until the user has been *still at the top* for a moment:
    /// arms near straight, shoulders not moving, for a full second. For squats,
    /// standing tall with the hips not moving.
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
    ///
    /// Squat setup is walking: prop the phone, walk back, turn round, settle.
    /// Every part of that moves the hips in frame and swings the shoulder-width
    /// yardstick as the body turns, so none of it is still, and the first thing
    /// that is - standing square to the camera for a second - is the top of a
    /// squat. The same test arms both.
    private var isArmed = false
    private var stillSince: Date?
    private var stillPrimaryLow = Double.infinity
    private var stillPrimaryHigh = -Double.infinity
    private var stillDropLow = Double.infinity
    private var stillDropHigh = -Double.infinity
    /// Between reps the same user rested at the top for 0.4-1.6s. A second is
    /// enough to fit the rest before a first rep and short enough that a set
    /// begun early arms at the next pause rather than never.
    private let armingStillness: TimeInterval = 1.0
    /// Set on the capture queue when the tracked person changes, so the main
    /// actor can drop the arming that belonged to someone else.
    private var subjectSwitched = false

    /// Leg evidence gathered since the last rep, when the legs are in shot.
    /// Push-ups only: for squats the legs *are* the rep, and these piles stay
    /// empty.
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
    /// Knees above the hands, in shoulder widths, *below* which the knees are on
    /// the floor.
    ///
    /// The hands are on the floor for the whole rep, which makes them the one
    /// fixed reference the frame has for floor level - and a knee at floor level
    /// is a knee that is kneeling.
    ///
    /// This number has been moved four times and every move was a guess dressed
    /// as a measurement, because head on there is nothing to measure: the legs
    /// point at the lens and a planted knee lands within a few pixels of a raised
    /// one. Side on it is ordinary geometry. A plank holds the knee a
    /// thigh-thickness clear of the floor - a good half a shoulder width - and
    /// kneeling puts it on the floor beside the hands, at roughly zero. The line
    /// sits between them, and `sawBodyLengthwise` is what stops it being applied
    /// where it cannot mean anything.
    private let kneelingKneeHeight: Double = 0.18
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

    private var isTooClose = false

    // MARK: - Descents the camera never saw
    //
    // The close-up failure, measured. A ten-rep set counted four: at the bottom
    // of nearly every rep Vision returned no body at all for about half a
    // second, and the frames either side of the gap had the arms still straight,
    // so there was never any travel to measure. Nothing was wrong with the
    // counting; the rep simply happened off camera.
    //
    // This is what that looks like from in here: the body disappears from the
    // top of a rep and reappears at the top of one. Two of those, with the
    // shoulders wide enough for a close-up to explain it, is enough to stop
    // guessing and say "back up" - roughly two reps in, rather than ten.

    /// The primary signal and the shoulder width as last measured, so the state
    /// at the moment the body vanished can be read after the fact.
    private var lastPrimarySeen: Double?
    private var lastWidthSeen: Double?
    /// When the current run of bodyless frames began.
    private var lostAt: Date?
    /// How long a gap has to be to count as a rep rather than a blink. The
    /// broken set's gaps ran 0.47 to 0.57s; ordinary joint blinks are a frame
    /// or two.
    private let blindDescentGap: TimeInterval = 0.25
    private let blindDescentsBeforeSpeaking = 2
    private var blindDescents = 0

    // MARK: - How the phone is standing
    //
    // Vision copes with a little lean and copes badly with a lot: past roughly
    // fifty degrees off vertical the body arrives foreshortened, and the
    // shoulder width that every height in this file is measured against stops
    // describing the same distance twice. A phone flat on the floor pointing at
    // the ceiling is the worst case and the most common one, and until now it
    // produced a screen that simply never counted, with nothing to suggest the
    // phone was the problem.
    //
    // Only the lean is read, never the heading: which way the user faces is
    // their business, and `RotationCoordinator` already handles portrait
    // against landscape.

    private let motion = CMMotionManager()
    /// Share of gravity running through the screen. 0 is standing upright, 1 is
    /// lying on its back. Generous on purpose, because propping a phone against
    /// a wall always leans it a little.
    private let flatGravity = 0.8
    /// Held, not glimpsed. A phone passes through flat on its way to being
    /// propped up, and a warning that flashes during setup is noise.
    private let tiltGrace: TimeInterval = 1.0
    private var tiltedSince: Date?
    private var isPhoneTilted = false


    /// How much of the *smallest* countable travel counts as "started descending".
    ///
    /// Measured against the corroborated travel, not the solo one, and for a
    /// reason that cost a rep: a close-grip rep with 25 degrees of travel only
    /// crossed the old 24.5 degree entry line at its very bottom, so the rep was
    /// "entered" and "returned" within a couple of frames and thrown out as too
    /// fast. Entering earlier lets a shallow-reading rep be timed in full.
    ///
    /// Then it happened again at 16 degrees. Vision loses the whole body for
    /// 0.4-0.9s at the bottom of a deep close-grip rep - the head fills the
    /// frame - so the descent has to be entered on the last frame before the
    /// loss or the rep is timed from the way back up and refused as too fast.
    /// Three of four reps crossed 16 degrees on exactly that last frame, one of
    /// them by 0.1 degree. Rest tops drift under 5 degrees, so 12 is still well
    /// clear of noise, and an early entry that goes nowhere is refused quietly.
    private let descentEntry = 0.6
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
        let movement = Movement.profile(for: exercise)
        self.movement = movement
        self.primaryTrack = SignalTrack(minimumSpan: movement.trackSpan, smoothing: 0.6)
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
        blindDescents = 0
        lastPrimarySeen = nil
        lastWidthSeen = nil
        lostAt = nil
        blocker = nil
        startTiltWatch()
        disarm()

        // Steps belong to the pedometer: there is no body movement for a camera
        // to watch. Failing loudly here is what routes them to `RepEngine`.
        guard Movement.supported.contains(exercise) else {
            tracking = .blocked("Rex can only watch push-ups and squats for now.")
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

    /// Called on the first frame with a body after a run without one. Decides
    /// whether what just happened off camera was a rep.
    private func noteRecovery(gap: TimeInterval) {
        guard gap >= blindDescentGap,
              let primary = lastPrimarySeen, primary >= movement.blindDescentTop,
              let width = lastWidthSeen, width > movement.tooCloseWidth
        else { return }
        blindDescents += 1
        if blindDescents >= blindDescentsBeforeSpeaking { isTooClose = true }
    }

    /// A flat phone outranks whatever else is true at the same time, because it
    /// is usually the cause of it: a phone on the floor is exactly how a body
    /// ends up cropped, and telling that user to back up sends them further
    /// from the fix.
    private func blocking(_ candidate: Blocker?) -> Blocker? {
        isPhoneTilted ? .phoneTilted : candidate
    }

    /// Watches the lean while the set runs. Read on the main queue and consumed
    /// by whichever queue asks, the same way the session is.
    private func startTiltWatch() {
        guard motion.isDeviceMotionAvailable else { return }
        isPhoneTilted = false
        tiltedSince = nil
        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            guard abs(gravity.z) > self.flatGravity else {
                self.tiltedSince = nil
                self.isPhoneTilted = false
                return
            }
            let since = self.tiltedSince ?? Date()
            self.tiltedSince = since
            self.isPhoneTilted = Date().timeIntervalSince(since) >= self.tiltGrace
        }
    }

    private func stopSession() {
        motion.stopDeviceMotionUpdates()
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
            widenFieldOfView(camera)
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

    /// Fits as much of the user in frame as the hardware allows.
    ///
    /// Being close to the phone is the normal way to use this: it is propped on
    /// the floor a few feet away while somebody does push-ups over it. The
    /// counter's failure there is not subtle - the wrists and knees leave the
    /// frame at the bottom of every rep, Vision reports nothing for them, and the
    /// rep is never judged. Nothing counts, and the screen gives no reason.
    ///
    /// Three things narrow the view, and iOS turns all of them on by itself:
    ///
    /// 1. **Centre Stage** crops into the sensor to keep a subject framed. It is a
    ///    system-wide setting the user may have enabled for video calls, it
    ///    applies here whether or not this app asked for it, and cropping in is
    ///    the exact opposite of what a body on the floor needs.
    /// 2. **The default format** is chosen for image quality, not coverage. Front
    ///    cameras publish several formats at the same resolution with genuinely
    ///    different fields of view, and the widest is often not the default.
    /// 3. **Residual zoom** carried over from whatever configured the device last.
    ///
    /// Widening costs nothing: pose estimation wants coverage far more than it
    /// wants pixels, and the format search is constrained to keep at least 720
    /// lines so the wrists still survive.
    private func widenFieldOfView(_ camera: AVCaptureDevice) {
        if AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }

        guard (try? camera.lockForConfiguration()) != nil else { return }
        defer { camera.unlockForConfiguration() }

        // The widest format that still has the pixels the wrists need. Formats are
        // compared on their published field of view, so this picks up whatever the
        // hardware actually offers rather than assuming a lens.
        let usable = camera.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return d.height >= 720 && d.width >= 1280
        }
        if let widest = usable.max(by: { $0.videoFieldOfView < $1.videoFieldOfView }),
           widest.videoFieldOfView > camera.activeFormat.videoFieldOfView {
            camera.activeFormat = widest
        }

        // A device handed back with zoom still applied silently undoes the format
        // choice above.
        if camera.videoZoomFactor != camera.minAvailableVideoZoomFactor {
            camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
        }
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
        /// The movement's own measure - elbow angle, or hips above knees.
        var primary: Double?
        /// Height in frame of the shoulders (push-ups) or hips (squats), in
        /// *current* shoulder widths. `consume` re-measures it against the
        /// resting width once armed; see `restingShoulderWidth` for why.
        var drop: Double?
        /// The shoulder width `drop` was divided by, so it can be re-measured.
        var shoulderWidth: Double?
        /// How far the ankles sit above the knees, in shoulder widths. Kneeling
        /// folds the shins up and pushes this positive; a plank keeps it at or
        /// below zero. Nil means the legs aren't in shot, which is not the same
        /// as kneeling. Push-ups only.
        var knee: Double?
        /// How far the knees sit above the wrists, in shoulder widths. Needs no
        /// ankles, which is the point: kneeling hides them. Nil when either the
        /// knees or the hands are out of shot. Push-ups only.
        var kneeHeight: Double?
        var frame: PoseFrame
        var isUsable: Bool { primary != nil || drop != nil }
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

        // The joints the whole measurement depends on are read at a lower bar
        // than the shoulders that anchor it: wrists and elbows for push-ups,
        // knees for squats, because they are the hardest to see and the ones a
        // frame cannot do without.
        func threshold(for joint: Joint) -> Float {
            movement.lenientJoints.contains(joint) ? 0.15 : minimumConfidence
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

        // --- Shoulder width: the yardstick for every height signal ---
        //
        // Measuring heights against the user's own shoulder width is what makes
        // them survive being closer to the phone than last time: both scale
        // together, so the ratio doesn't care about distance.
        let leftShoulder = measured(.leftShoulder)
        let rightShoulder = measured(.rightShoulder)

        var width = lastShoulderWidth
        if let l = leftShoulder, let r = rightShoulder {
            let seen = Double(hypot(l.x - r.x, l.y - r.y))
            if seen > 0.02 {
                width = seen
                lastShoulderWidth = seen
                lastWidthSeen = seen
                // Width alone never raises the flag any more: an honest close set
                // measures the same as a broken one at the bottom of a rep, and
                // the difference between them is whether the camera still sees
                // the descent. `noteRecovery` is what raises it. Coming back
                // under the line does clear it, because that is the one thing
                // the width can say by itself - they backed up.
                if seen <= movement.tooCloseWidth {
                    isTooClose = false
                    blindDescents = 0
                }
            }
        }

        // A second opinion on distance, for the case the check above cannot see.
        //
        // That one can only speak when both shoulders are in shot - and the way
        // people actually get too close is by pushing a shoulder out of frame.
        // `seen` is then never computed, `isTooClose` keeps whatever it already
        // held, and for anybody who was too close from the very first frame that
        // is `false` forever. They get no reps and no explanation, which is the
        // worst pair of things this screen can do at once.
        //
        // Essentials gone while the body is jammed against an edge says the same
        // thing and needs no particular joint to say it. Only ever raises the
        // flag; clearing it stays with the shoulder measurement above, which is
        // the one that can tell "stepped back far enough" from "still hidden".
        let essentials = movement.lenientJoints
        if !essentials.isEmpty {
            let missing = essentials.filter { raw($0) == nil }.count
            if missing * 2 > essentials.count {
                let confident = recognized.values
                    .filter { $0.confidence > 0.15 }
                    .map { $0.location }
                let againstEdge = confident.contains {
                    $0.x < 0.02 || $0.x > 0.98 || $0.y < 0.02 || $0.y > 0.98
                }
                if confident.count >= 3, againstEdge { isTooClose = true }
            }
        }

        // --- The two signals ---
        //
        // The one place in the file that knows a push-up is arms and a squat is
        // legs. Everything downstream sees `primary` and `drop` and does not
        // care which joints made them.
        var primary: Double?
        var drop: Double?
        var ankleLift: Double?
        var kneeHeight: Double?

        switch movement.kind {
        case .pushUp:
            // --- Elbow angle: the more bent of whichever arms are fully visible ---
            //
            // Not the average. Head-on, one arm of a close-grip push-up is seen
            // almost end-on: shoulder, elbow and wrist line up in the image and the
            // angle reads 173-175 degrees at the very bottom of a rep that visibly
            // bends the other arm to 128-156. Averaged, four honest reps read 15-17
            // degrees of travel - under the line that starts a descent - and two of
            // them were never judged at all, silently, while the two that counted did
            // so only because a hidden wrist was re-detected up at elbow height. The
            // more bent arm read 25-43 degrees on the same four reps. Both arms
            // bend the same amount in reality; the camera only ever gets a clean
            // look at one of them.
            func arm(_ shoulder: Joint, _ elbow: Joint, _ wrist: Joint) -> Double? {
                guard let s = measured(shoulder), let e = measured(elbow), let w = measured(wrist) else { return nil }
                return angle(s, e, w)
            }
            let arms = [arm(.leftShoulder, .leftElbow, .leftWrist),
                        arm(.rightShoulder, .rightElbow, .rightWrist)].compactMap { $0 }
            primary = arms.min()

            // --- Shoulder height, in shoulder-widths ---
            //
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

                // How side-on the body is, as the horizontal gap between the
                // hands and the feet in shoulder widths.
                //
                // This is the measurement the knee gate was missing, and the
                // reason it could never be made to work by moving thresholds.
                // Filmed head-on, the legs point at the lens: hip, knee and ankle
                // project to nearly one point, the knee sits a few pixels from the
                // wrist whether it is planted or not, and there is simply no
                // signal there to threshold. Side on, a plank stretches three or
                // four shoulder widths across the frame and the knee is a hand's
                // height above the floor line the hands and feet define. Same
                // arithmetic, completely different amount of information.
                let wristsX = [measured(.leftWrist)?.x, measured(.rightWrist)?.x].compactMap { $0 }
                let anklesX = [measured(.leftAnkle)?.x, measured(.rightAnkle)?.x].compactMap { $0 }
                if !wristsX.isEmpty, !anklesX.isEmpty {
                    let handX = Double(wristsX.reduce(0, +)) / Double(wristsX.count)
                    let footX = Double(anklesX.reduce(0, +)) / Double(anklesX.count)
                    bodySpread = abs(handX - footX) / width
                }
            }

        case .squat:
            // --- Thigh pitch: hips above knees, in shoulder-widths ---
            //
            // Not the knee angle, and for the same reason the knee push-up gate
            // could not use it. The user faces the camera, so at the bottom of a
            // squat the thigh points straight at the lens and its projected length
            // collapses. What is left of the hip-knee segment in the image is the
            // sideways offset of the hip inboard of the knee, so the angle Vision
            // would measure at the knee is atan(thigh height / stance offset):
            // depth divided by stance width. It sits near 170 for the first half
            // of the descent, then swings 60 degrees over the last quarter, and
            // where it lands is decided by how wide the feet are and how far the
            // knees track out, neither of which is the thing being judged. A
            // narrow stance makes it noise outright, exactly as the plank did.
            //
            // The vertical component alone survives the projection, and it *is*
            // depth: hips a full thigh above the knees standing, level with them at
            // parallel, below them past it. Measured in shoulder widths. Femur and
            // biacromial width are both close to a quarter of stature, so standing
            // this reads about 1.0-1.2, and the whole squat is a fall towards zero.
            // Same shape as the elbow angle, so the same state machine times it.
            //
            // Both legs averaged, unlike the arms. The min-of-arms fix exists
            // because head-on one arm is seen end-on and reads straight while the
            // other bends; facing the camera, neither leg is end-on and both hips
            // and both knees are in plain view, so there is no side the camera is
            // systematically wrong about. Averaging halves a one-frame slip of a
            // single knee, which is the failure this view actually has. If footage
            // shows one knee wandering up the thigh at the bottom, take the deeper
            // leg (the smaller gap) rather than the average - never the shallower.
            //
            // Two things this cannot see, said plainly so footage can check them.
            // The phone is low - on the floor, most likely - and the knees come
            // towards it at the bottom, so perspective lifts them in frame: from a
            // floor-level phone two metres away a parallel squat reads about -0.2
            // here and a half squat about 0.3; from a table at hip height the same
            // two read about +0.1 and 0.6. And the shoulders lean towards the lens
            // at the bottom, widening the yardstick by roughly a tenth, which
            // shrinks every reading taken there. `Movement.squats` is set with both
            // in mind and the HUD prints the shoulder width so a recording can say
            // how far off this arithmetic was.
            let hips = [measured(.leftHip)?.y, measured(.rightHip)?.y].compactMap { $0 }
            let knees = [measured(.leftKnee)?.y, measured(.rightKnee)?.y].compactMap { $0 }
            if let width, width > 0.02, !hips.isEmpty {
                let hipY = Double(hips.reduce(0, +)) / Double(hips.count)
                if !knees.isEmpty {
                    let kneeY = Double(knees.reduce(0, +)) / Double(knees.count)
                    // Vision's origin is bottom-left, so hips above knees is positive.
                    primary = (hipY - kneeY) / width
                }

                // --- Hip height, in shoulder-widths ---
                //
                // The corroborating signal, playing the shoulders' part. The hips'
                // own travel is the better depth measure of the two - it barely
                // cares where the phone is, because hips and knees are the same
                // distance from the lens whether it is on the floor or a table -
                // but it is a *frame position*, not a body measure, and that is why
                // it cannot lead. Stepping back from a floor-level phone sinks the
                // hips towards the horizon and shrinks the yardstick at once, which
                // reads as well over a shoulder width of "drop" on straight legs.
                // A knocked phone does the same. The thigh pitch above ignores both,
                // so it decides, and this has to agree.
                drop = (1 - hipY) / width
            }
        }

        // --- Joints to draw ---
        var joints: [PoseFrame.Joint: CGPoint] = [:]
        for (key, name) in PoseFrame.visionJoints {
            if let p = raw(name) { joints[key] = CGPoint(x: p.x, y: 1 - p.y) }
        }

        let reading = Reading(primary: primary, drop: drop, shoulderWidth: width,
                              knee: ankleLift, kneeHeight: kneeHeight,
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
        // The height signal in top-of-rep shoulder widths, not this frame's.
        // Both are the same number until the count arms; after that the
        // difference is the difference between a signal that reads the same way
        // up every rep and one that reversed on a second user. See
        // `restingShoulderWidth`.
        var rawDrop = reading.drop
        if let d = reading.drop, let seen = reading.shoulderWidth,
           let resting = restingShoulderWidth, resting > 0.02 {
            rawDrop = d * seen / resting
        }
        _ = reading.primary.map { primaryTrack.push($0) }
        _ = rawDrop.map { dropTrack.push($0) }
        let primary = reading.primary != nil ? primaryTrack.current : nil
        let drop = rawDrop != nil ? dropTrack.current : nil

        repWindow.observe(primary: primary, drop: drop)
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
        if let spread = bodySpread { repSpreads.append(spread) }
        if let pending = pendingRep {
            settle(pending, dropNow: drop)
        }

        #if DEBUG
        // One line per movement, not one line for both. These are read off
        // screen recordings by a person, and each movement's line is the set of
        // numbers that movement's constants were - or will be - tuned on. The
        // push-up line is left exactly as it was so old recordings still read.
        let status = isArmed ? (pendingRep != nil ? "wait" : "armed") : "hold"
        switch movement.kind {
        case .pushUp:
            diagnostics = String(
                format: "e %@ · top %@ btm %@ · drop %@ · lift %@ · knee %@ · spread %@ · %@%@",
                primary.map { String(format: "%.0f°", $0) } ?? "-",
                repTop.map { String(format: "%.0f", $0) } ?? "-",
                repBottom.map { String(format: "%.0f", $0) } ?? "-",
                repWindow.dropTravel.map { String(format: "%.2f", $0) } ?? "-",
                repAnkleLifts.last.map { String(format: "%+.2f", $0) } ?? "-",
                repKneeHeights.last.map { String(format: "%+.2f", $0) } ?? "-",
                bodySpread.map { String(format: "%.1f", $0) } ?? "-",
                status,
                rejectionSummary
            )
        case .squat:
            // `gap` is hips above knees, `hip` the hips' height in frame (both in
            // shoulder widths), `sw` the shoulder width as a share of frame
            // height - the perspective and too-close questions both hang on it.
            diagnostics = String(
                format: "gap %@ · top %@ btm %@ · hip %@ drop %@ · sw %@ · %@%@",
                primary.map { String(format: "%+.2f", $0) } ?? "-",
                repTop.map { String(format: "%.2f", $0) } ?? "-",
                repBottom.map { String(format: "%.2f", $0) } ?? "-",
                drop.map { String(format: "%.2f", $0) } ?? "-",
                repWindow.dropTravel.map { String(format: "%.2f", $0) } ?? "-",
                lastShoulderWidth.map { String(format: "%.2f", $0) } ?? "-",
                status,
                rejectionSummary
            )
        }
        #endif

        guard let primary else {
            formHint = movement.needSignalHint
            blocker = blocking(.bodyNotInShot)
            return
        }

        if !isArmed {
            updateArming(primary: primary, drop: drop)
            // Armed on this frame: the user has just held the top still for a
            // second, so this frame's shoulder width is the top width.
            if isArmed { restingShoulderWidth = reading.shoulderWidth }
        } else if let seen = reading.shoulderWidth, let resting = restingShoulderWidth,
                  !isDown, pendingRep == nil, primary >= movement.restingTop {
            // Between reps, arms straight: follow the top width slowly so a user
            // who shifts closer to the phone is re-measured. Never during a
            // descent, where the width is the thing that misleads.
            restingShoulderWidth = resting + (seen - resting) * restingWidthFollow
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
            repTop = max(repTop ?? primary, primary)
            repBottom = primary
            let entryTravel = (sawBodyLengthwise && movement.kind == .pushUp)
                ? movement.sideOnCorroboratedTravel : movement.corroboratedTravel
            if isArmed, let top = repTop, top - primary >= entryTravel * descentEntry {
                isDown = true
                let now = Date()
                repWindow.startedDownAt = now
                repWindow.rescopeDrop(
                    topFrom: recentDrops.map(\.drop),
                    bottomFrom: recentDrops.filter { now.timeIntervalSince($0.at) <= dropLeadLookback }.map(\.drop)
                )
                // Descending again with the last rep still waiting on the
                // shoulders means they never came back up, so it wasn't a rep.
                if let pending = pendingRep {
                    pendingRep = nil
                    refuseReturn(pending)
                }
            }
        } else {
            repBottom = min(repBottom ?? primary, primary)
            if let top = repTop, let bottom = repBottom {
                let excursion = top - bottom
                if excursion > 0, primary >= bottom + excursion * ascentReturn {
                    isDown = false
                    judgeRep(top: top, bottom: bottom, dropNow: drop)
                    // Carry the top forward rather than reseeding it from wherever
                    // the arm happens to be. Someone tiring stops locking out, so a
                    // top taken from the last rep's end creeps down until the travel
                    // gate starts eating honest reps - which is what turned fifteen
                    // push-ups into ten.
                    repTop = max(primary, top - movement.topCarry)
                    repBottom = primary
                }
            }
        }

        if let top = repTop, let bottom = repBottom {
            depth = max(0, min(1, (top - primary) / max(movement.minTravel, top - bottom)))
        }
        // A rejection has the floor until it times out. Anything else here would
        // wipe it before it could be read.
        if let expiry = hintExpiresAt, expiry > Date() { return }
        hintExpiresAt = nil

        blocker = blocking(isTooClose ? .tooClose : nil)

        if isTooClose {
            formHint = movement.tooCloseHint
        } else if isPhoneTilted {
            formHint = nil
        } else if movement.checksKneeling, !hasSeenLegs, reps == 0 {
            // Said once, gently: with the legs out of shot the count still works,
            // it just can't tell a push-up from a knee push-up.
            formHint = "Step back if you can - Rex counts best with your legs in shot."
        } else {
            formHint = nil
        }
    }

    /// Decides whether the movement just completed was a rep.
    ///
    /// Corroboration is the rule: when the height signal was visible too, it has
    /// to agree. A genuine push-up bends the elbows *and* drops the shoulders, a
    /// genuine squat pitches the thighs *and* drops the hips, so requiring both
    /// is what separates a rep from the two easy fakes — bobbing the body with
    /// the joints locked, and flexing the joints without lowering the body. The
    /// primary signal is never optional, in either direction: a downward dog
    /// drops the shoulders through a huge range on straight arms, a step back
    /// from a low phone drops the hips through a huge range on straight legs,
    /// and any check that lets height travel vote alone counts those as a set.
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
        //
        // Squats gather no leg samples, so both piles are empty and neither
        // verdict can fire. The squat's cheat is the half-rep, and that is judged
        // on depth below.
        // Only judge the legs when the camera could actually see them.
        //
        // Filmed down the length of the body there is no separation between a
        // planted knee and a lifted one, and every version of this gate that
        // tried anyway has both refused honest reps and passed knee push-ups -
        // which is exactly what a threshold on noise does. With the body side on
        // the same measurement separates cleanly, so the test now runs there and
        // stands down everywhere else.
        if sawBodyLengthwise {
            let kneesDown = kneelingVerdict(downKneeHeights, says: { $0 < kneelingKneeHeight })
            let anklesUp = kneelingVerdict(downAnkleLifts, says: { $0 > kneelingLift })
            if kneesDown || anklesUp {
                reject("knees", "Knees are down - straighten your legs to count.")
                return
            }
        }

        if duration < minimumRepDuration {
            reject("fast", "Too fast to read - lower under control.", quietly: true)
            return
        }

        let drop = repWindow.dropTravel
        let travel = top - bottom

        // A strong drop, seen for the whole rep, vouches for the primary signal
        // and relaxes its gates. Without it the primary signal stands alone and
        // has to prove the rep by itself.
        let corroborated = drop.map { $0 >= movement.strongDropTravel } == true && repWindow.sawDropThroughout
        // A drop well beyond what anything but a rep produces vouches harder
        // still, and the elbow then only has to have started a descent. Head on,
        // that is the difference between counting a set and refusing half of it:
        // see `Movement.pushUps.deepDropTravel`.
        let deep = drop.map { $0 >= movement.deepDropTravel } == true && repWindow.sawDropThroughout

        // How strict to be depends on how well the camera could see.
        //
        // Every push-up threshold in this file was set against head-on footage,
        // where the upper arm is foreshortened and a genuinely deep rep reads
        // 25-31 degrees of travel bottoming at 116-129. They had to be that
        // forgiving to count real work through a lens that was hiding most of it.
        //
        // Side on, nothing is hidden: a full push-up swings the elbow through
        // 70-90 degrees and bottoms near a right angle. Applying the forgiving
        // numbers to an honest measurement is what let a quarter rep through -
        // 30 degrees of travel is most of a rep when it is being under-read, and
        // barely a dip when it is not.
        let strict = sawBodyLengthwise && movement.kind == .pushUp
        let requiredTravel = strict
            ? (corroborated ? movement.sideOnCorroboratedTravel : movement.sideOnMinTravel)
            : (deep ? movement.deepCorroboratedTravel
               : corroborated ? movement.corroboratedTravel
               : drop == nil ? movement.soloTravel : movement.minTravel)
        let allowedBottom = strict
            ? (corroborated ? movement.sideOnCorroboratedBottom : movement.sideOnMaxBottom)
            : (deep ? movement.deepCorroboratedBottom
               : corroborated ? movement.corroboratedBottom : movement.maxBottom)

        guard travel >= requiredTravel else {
            reject("travel", movement.shallowHint, quietly: brief)
            return
        }
        guard bottom <= allowedBottom else {
            reject("locked", movement.lockedHint, quietly: brief)
            return
        }
        // The body has to come down, which is the second of the two things a
        // rep actually is. Only judged when the height signal was visible for
        // most of the rep, and at a threshold well under a real rep's travel, so a
        // blink in tracking can't refuse honest work.
        if let drop, repWindow.sawDropThroughout, drop < movement.minDropTravel {
            reject("chest", movement.noDropHint)
            return
        }
        // And the body has to come back. Shoulders that are still at their
        // lowest when the elbows have straightened were not doing a push-up; they
        // were arriving somewhere - typically the floor, at the start of a set.
        // Or the elbow reading ran ahead of the body, which is why the rep waits
        // rather than being refused on the spot.
        if let drop, repWindow.sawDropThroughout, drop >= movement.minDropTravel {
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

    /// Banks a waiting rep the moment the body is back up, or refuses it once it
    /// has had long enough and hasn't come.
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
        reject("return", movement.noReturnHint)
    }

    private func clearLegSamples() {
        repAnkleLifts = []
        repKneeHeights = []
        downAnkleLifts = []
        downKneeHeights = []
        repSpreads = []
    }

    /// Whether the camera saw enough of the body's length for a leg judgement to
    /// carry any information.
    ///
    /// Below this the hands and feet are nearly on top of each other in frame,
    /// which is what filming down the length of a plank looks like - and in that
    /// view a planted knee and a raised one land within a few pixels of each
    /// other. Refusing to judge is the honest answer there. It is also why this
    /// gate could never be fixed by moving a threshold: the number it was reading
    /// did not contain the answer.
    private var sawBodyLengthwise: Bool {
        guard let spread = median(of: repSpreads) else { return false }
        return spread >= minimumBodySpread
    }

    /// Two shoulder widths between hands and feet. A plank seen properly side on
    /// spans three or four; seen head on it spans well under one.
    private var minimumBodySpread: Double { 2.0 }

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
    /// has held the top of a rep for `armingStillness`. Any frame that isn't a
    /// still top - arms bent or thighs pitched, body moving, height unseen -
    /// starts the clock again.
    @MainActor
    private func updateArming(primary: Double, drop: Double?) {
        let now = Date()
        guard let drop, primary >= movement.restingTop else {
            resetStillness()
            return
        }
        stillPrimaryLow = min(stillPrimaryLow, primary)
        stillPrimaryHigh = max(stillPrimaryHigh, primary)
        stillDropLow = min(stillDropLow, drop)
        stillDropHigh = max(stillDropHigh, drop)
        if stillPrimaryHigh - stillPrimaryLow > movement.stillRange || stillDropHigh - stillDropLow > movement.stillDropRange {
            // Restart from this frame rather than from nothing, so a single
            // outlier costs one second and not two.
            resetStillness()
            stillPrimaryLow = primary; stillPrimaryHigh = primary
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
        repTop = primary
        repBottom = primary
        isDown = false
    }

    private func resetStillness() {
        stillSince = nil
        stillPrimaryLow = .infinity
        stillPrimaryHigh = -.infinity
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
        restingShoulderWidth = nil
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
        // A counted rep outranks whatever was being said about the last one.
        // Without this a refusal kept the floor for its full 2.5 seconds: one
        // set ended with "Not deep enough" in red over a rep that counted and
        // banked the set, which is the counter contradicting itself on screen.
        formHint = nil
        blocker = nil
        hintExpiresAt = nil
        Haptics.rep()
        if reps >= target { stop() }
    }
}

// MARK: - Movements

/// Everything that is different about counting one movement rather than another,
/// and nothing that isn't.
///
/// The split falls here because the *shape* of a rep is the same for both
/// movements: one body-internal measure that falls on the way down and comes
/// back (an elbow angle, a thigh pitch), and one frame-position height that has
/// to agree with it (shoulders dropping, hips dropping). Everything that acts on
/// that shape - the turning-point state machine, the stillness arming, subject
/// lock-on, joint memory, the pending-return wait and the rejection ladder - is
/// written once against `primary` and `drop` and never learns which joints it is
/// looking at. What changes is which joints produce the two signals, how far
/// they move in a real rep, and what to tell the user when they don't. That is
/// what lives here. A movement-specific branch anywhere else in the file is a
/// smell: either it belongs in this struct, or the shared machinery is wrong.
///
/// Every threshold is in the primary signal's own units - degrees for push-ups,
/// shoulder widths for squats - and every one of them means the same thing in
/// both: "this far, or it wasn't a rep". The push-up numbers come from footage.
/// The squat numbers come from geometry and say so.
private struct Movement {
    enum Kind { case pushUp, squat }
    let kind: Kind

    /// Joints read at a lower confidence bar than the rest, because the
    /// measurement cannot do without them and they are the hardest to see.
    let lenientJoints: Set<VNHumanBodyPoseObservation.JointName>
    /// `SignalTrack.minimumSpan` for the primary signal. Inert since counting
    /// moved to turning points, kept honest per movement anyway.
    let trackSpan: Double

    /// How far the primary signal has to fall for a rep, with the height signal
    /// merely present; and on its own, with no height signal at all.
    let minTravel: Double
    let soloTravel: Double
    /// The lowest the primary signal has to get. Travel alone can be produced by
    /// starting already folded; this insists on a real bottom position.
    let maxBottom: Double
    /// A drop this big, seen throughout, vouches for the primary signal and
    /// relaxes its two gates to the corroborated pair below.
    let strongDropTravel: Double
    let corroboratedTravel: Double
    let corroboratedBottom: Double
    /// A drop this big, seen throughout, is more than corroboration: nothing
    /// but a rep produces it, and the primary signal then only has to show that
    /// a descent happened at all. Set to infinity to disable the tier.
    let deepDropTravel: Double
    let deepCorroboratedTravel: Double
    let deepCorroboratedBottom: Double
    /// The same two gates for a camera that can actually see the arm bend.
    /// Meaningless for squats, which are filmed facing the lens either way, so
    /// they simply repeat the ordinary numbers.
    let sideOnMinTravel: Double
    let sideOnMaxBottom: Double
    let sideOnCorroboratedTravel: Double
    let sideOnCorroboratedBottom: Double
    /// The least the height signal may drop, when it was tracked throughout,
    /// before the rep is refused for the body not having come down.
    let minDropTravel: Double

    /// A top the arming test will accept: arms at least this straight, thighs
    /// at least this tall.
    let restingTop: Double
    /// How much the two signals may wander over `armingStillness` and still be
    /// "still".
    let stillRange: Double
    let stillDropRange: Double
    /// How far the carried-forward top may fall behind the last one after a rep.
    let topCarry: Double
    /// Shoulder width as a share of frame height, past which the body is close
    /// enough that a close-up is *possible*. Never enough on its own; see
    /// `blindDescentTop`.
    let tooCloseWidth: Double
    /// The primary signal above which the body is still at the top of a rep.
    ///
    /// Used to recognise a descent the camera never saw: if the body vanishes
    /// while the arms are still near straight, and comes back a moment later,
    /// whatever happened in between was a rep with no evidence in it.
    let blindDescentTop: Double
    /// Whether the knee-push-up gate is live: whether leg samples are gathered
    /// and the "legs in shot" hint is shown.
    let checksKneeling: Bool

    let needSignalHint: String
    let tooCloseHint: String
    let lostBodyHint: String
    let shallowHint: String
    let lockedHint: String
    let noDropHint: String
    let noReturnHint: String

    static let supported: [Exercise] = [.pushUps, .squats]

    static func profile(for exercise: Exercise) -> Movement {
        switch exercise {
        case .pushUps: return .pushUps
        case .squats:  return .squats
        // Steps never reach the camera - `start()` refuses them before a frame
        // is read - so this only has to be something, not the right thing.
        case .steps:   return .pushUps
        }
    }

    /// Push-ups. Every number below was moved because a frame-by-frame reading
    /// of real footage said so; see CLAUDE.md for the history. None of them is
    /// to be touched without a measurement that justifies it.
    static let pushUps: Movement = {
        /// How far a real push-up moves. Degrees of elbow bend, and shoulder height in
        /// shoulder-widths. Both are well inside what a genuine rep covers — a full
        /// push-up bends the elbow through 70-90 degrees — and well outside what
        /// bouncing on the spot produces.
        let minElbowTravel: Double = 35
        let minDropTravel: Double = 0.12
        /// With no shoulder drop to corroborate it, the elbow has to clear a higher
        /// bar on its own.
        let soloElbowTravel: Double = 45
        /// How bent the elbow has to get at the bottom. A real push-up finishes near
        /// a right angle; anything that keeps the arms locked out sits far above this
        /// however far the rest of the body travels.
        let maxBottomAngle: Double = 145
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
        ///
        /// Was 0.35, lowered because the drop was then measured in *current*
        /// shoulder widths and the width grew 386 to 547 pixels in one rep, which
        /// shrank a full-depth rep to a coin flip against 0.35. The drop is now
        /// measured in the resting width (see `restingShoulderWidth`), so a real
        /// rep reads far larger: 0.38-1.27 across four recordings, forty-five
        /// reps, none under 0.38. Left at 0.30 rather than raised, because the
        /// smallest of those were a second person's knee push-ups and 0.30 is
        /// still clear of everything that wasn't a rep: rests held within 0.05,
        /// a one-armed reach for the phone made 0.24-0.28.
        let strongDropTravel: Double = 0.30
        let corroboratedElbowTravel: Double = 20
        let corroboratedBottomAngle: Double = 155
        /// The deep-drop tier, from four screen recordings read frame by frame at
        /// 6fps against the skeleton Vision drew.
        ///
        /// Head on, the elbow angle under-reads the bottom of a full push-up so
        /// badly that honest reps straddle the 20 degree gate above. With the
        /// phone close (bedroom clip) six of eleven full-depth reps were refused
        /// "Not deep enough", every one of them with the chest on the floor and
        /// the head filling the frame; the elbow read 12-27 degrees of travel
        /// on them and bottomed at 142-153. A dark hallway clip lost two of
        /// twelve the same way (14 and 27 degrees), a good-light clip one of
        /// eleven. On every one of those the shoulders had dropped 0.41-0.84 of
        /// the resting shoulder width, which no movement in any of the four
        /// clips other than a push-up came near: rests held within 0.05, a reach
        /// for the phone made 0.24-0.28, sitting back onto the knees and coming
        /// forward again made 0.33. So past 0.45, starting a descent is enough:
        /// the elbow gate falls to the entry travel, and the bottom to 160,
        /// which rest tops (155-180 in the same footage) clear with room. The
        /// elbow is still not optional - a descent has to be entered - so a
        /// downward dog on locked arms is refused as before, and the return
        /// check still refuses anything that finishes at the bottom.
        let deepDropTravel: Double = 0.45
        let deepElbowTravel: Double = 12
        let deepBottomAngle: Double = 160
        /// Rest tops in real footage read 155-180 degrees and drifted under 5 degrees
        /// frame to frame; the shoulders held to within 0.08 shoulder widths.
        let restingElbow: Double = 150
        let stillElbowRange: Double = 15
        /// Shoulder width as a share of the frame *height*, past which a body is
        /// close enough for the close-up failure to be possible.
        ///
        /// 0.55 used to sit here and could never be reached: the buffer is
        /// portrait (720 wide, 1280 tall) and `measured` scales x by width over
        /// height, so two shoulders both inside the frame span at most 0.5625 of
        /// its height. The check never fired, and a ten-rep set that counted
        /// four said nothing about why.
        ///
        /// 0.24 comes off four screen recordings replayed through this same
        /// Vision request. Three sets that counted correctly measured 0.096 to
        /// 0.232 (medians 0.128, 0.176, 0.182); the set that counted 4 of 10
        /// never went below 0.275 and ran 0.275 to 0.395 (median 0.316).
        ///
        /// It is still not enough on its own, and the reason is in the history:
        /// an honest close set reached 0.34 to 0.37 at the bottom of reps that
        /// counted, which overlaps the broken set. A width line low enough to
        /// catch the close-up would nag someone whose reps are counting, so the
        /// width only opens the question and `blindDescentTop` answers it.
        let tooCloseWidth: Double = 0.24
        /// Rest tops read 155-180 degrees, so arms above 140 are still straight.
        ///
        /// In the broken set every one of the eleven dropouts began between 150
        /// and 162 degrees: the body left the frame before it had bent at all,
        /// and came back 0.5s later at the top. In the three sets that counted,
        /// the dropouts began at 54 to 89 degrees - already deep, with the
        /// travel measured before the blink.
        let blindDescentTop: Double = 140

        return Movement(
            kind: .pushUp,
            // Wrists and elbows are the hardest joints to see and the ones the
            // whole measurement depends on.
            lenientJoints: [.leftWrist, .rightWrist, .leftElbow, .rightElbow],
            trackSpan: 18,
            minTravel: minElbowTravel,
            soloTravel: soloElbowTravel,
            maxBottom: maxBottomAngle,
            strongDropTravel: strongDropTravel,
            corroboratedTravel: corroboratedElbowTravel,
            corroboratedBottom: corroboratedBottomAngle,
            deepDropTravel: deepDropTravel,
            deepCorroboratedTravel: deepElbowTravel,
            deepCorroboratedBottom: deepBottomAngle,
            // Side on, where the elbow angle is what it says it is. A full
            // push-up swings through 70-90 degrees and finishes near a right
            // angle; a quarter rep manages about 30 and stops around 140, which
            // is why it sailed through gates built for a foreshortened view.
            // 55 and 120 sit between the two with room on both sides, and the
            // corroborated pair stay 15 degrees more forgiving as they do above.
            sideOnMinTravel: 55,
            sideOnMaxBottom: 120,
            sideOnCorroboratedTravel: 40,
            sideOnCorroboratedBottom: 135,
            minDropTravel: minDropTravel,
            restingTop: restingElbow,
            stillRange: stillElbowRange,
            // The shoulders may wander as much as the smallest countable drop
            // and still be "still"; that is the line the footage was read against.
            stillDropRange: minDropTravel,
            // Someone tiring stops locking out, so the top is allowed to creep
            // down by this much per rep rather than being reseeded from wherever
            // the arm happens to be.
            topCarry: 15,
            tooCloseWidth: tooCloseWidth,
            blindDescentTop: blindDescentTop,
            checksKneeling: true,
            needSignalHint: "Rex needs to see your elbows. Get your hands in frame.",
            tooCloseHint: "Back up a little bit before continuing. Rex loses your arms at the bottom.",
            lostBodyHint: "Stand the phone up facing you, past your hands.",
            shallowHint: "Not deep enough - bend your elbows further.",
            lockedHint: "Arms stayed straight - bend them to count.",
            noDropHint: "Chest didn't drop - lower all the way down.",
            noReturnHint: "Push all the way back up to count."
        )
    }()

    /// Squats. **Nothing here has been checked against footage yet.** Every
    /// number is derived from the geometry in `read()` and labelled by how much
    /// it is trusted; the first screen recording with a known count decides
    /// which of them move. The HUD prints `gap`, `hip`, `drop` and `sw` so that
    /// reading can be done frame by frame, as the push-up numbers were.
    ///
    /// The geometry, once, so each constant below can refer to it. Standing, the
    /// hips sit about one shoulder width above the knees (femur and biacromial
    /// width are both roughly a quarter of stature; call it 1.05-1.2 depending
    /// on build - **the first thing footage will correct**). Then, in shoulder
    /// widths, hips above knees / hip drop for each depth, from a floor-level
    /// phone and from a hip-height table, both two metres away:
    ///
    ///   quarter squat (thigh 45 degrees)   gap 0.60 / 0.75   drop 0.40 / 0.33
    ///   half squat (60)                    gap 0.31 / 0.63   drop 0.63 / 0.53
    ///   just above parallel (75)           gap 0.07 / 0.41   drop 0.90 / 0.77
    ///   parallel (90)                      gap -0.18 / 0.13  drop 1.07 / 1.07
    ///
    /// Perspective lifts the knees as they come towards a low lens, which is why
    /// the floor column reads deeper; the hips' own drop hardly notices where
    /// the phone is. Every bottom reading then shrinks by about a tenth because
    /// the shoulders lean in and widen the yardstick.
    ///
    /// The line is drawn between a quarter squat and a half squat, not between
    /// a half squat and parallel. Those last two are fifteen degrees of thigh
    /// and a hand's width of hip height apart, and a single camera that does
    /// not know where it is standing cannot split them without also refusing
    /// honest just-above-parallel reps from a table. So a half squat is let
    /// through when the camera is low, refused when it is high, and a quarter
    /// squat - the four-inch dip - is refused from everywhere by two gates at
    /// once. A parallel squat clears every gate by at least 0.35 from either
    /// placement, which is the margin that matters. Refusing real work costs
    /// belief in the counter; a missed half squat costs minutes.
    static let squats: Movement = {
        /// Hips above knees at the bottom, in shoulder widths, above which the
        /// thighs never got near parallel.
        ///
        /// From the table above: parallel reads -0.2 to +0.1, just-above-parallel
        /// 0.07-0.41, a half squat 0.3-0.6. Set at 0.55 rather than 0.5 so the
        /// honest just-above-parallel rep from a table camera keeps 0.14 rather
        /// than 0.09 - thin either way, and said plainly: **this is the one
        /// margin honest form does not have much of**, and a recording of
        /// someone squatting to a hand above parallel with the phone on a table
        /// is the footage that settles it. Half squats from a table read at the
        /// line and will go either way; that is the bias, chosen on purpose.
        let maxBottomGap: Double = 0.55
        /// How far the hips have to fall towards the knees. Standing about 1.1,
        /// parallel about zero, so a full rep travels about a shoulder width and
        /// a half squat about half of one. Set at the half squat's own reading so
        /// a quarter squat (0.3-0.5 of travel) is well under it and parallel has
        /// more than double. A guess in its exact value, not in its role.
        let minGapTravel: Double = 0.45
        /// With no hip height to corroborate. Hips and knees give the gap, hips
        /// and shoulders give the height, so in practice one exists whenever the
        /// other does and this branch cannot arise; it is set equal to the
        /// ordinary travel so that if it ever does, nothing tightens.
        let soloGapTravel: Double = 0.45
        /// A hip drop this big, seen throughout, vouches for the thigh pitch.
        ///
        /// This is what saves a parallel squat filmed from a high shelf: with the
        /// lens above the hips, perspective pushes the knees *down* in frame and
        /// a genuine parallel squat reads about 0.42 on the gap - inside the
        /// gate, but barely - while its hips have dropped a full shoulder width
        /// regardless. Just-above-parallel reads 0.77-0.90, a half squat
        /// 0.53-0.63 (shrinking to about 0.5-0.57 as the shoulders lean in), so
        /// 0.75 is cleared by any honest rep and by no half squat. Guess: the
        /// half-squat ceiling and the just-above-parallel floor are 0.15 apart
        /// and this sits between them; footage of both depths moves it.
        let strongHipDrop: Double = 0.75
        /// With the hips vouching, the gap need only show the thighs genuinely
        /// pitched and got most of the way down. Entry into a descent is 0.6 of
        /// the travel figure (`descentEntry`), so 0.21 of a shoulder width, which
        /// is three or four times the standing jitter estimated below. Both
        /// guesses.
        let corroboratedGapTravel: Double = 0.35
        let corroboratedBottomGap: Double = 0.65
        /// The least the hips may drop when tracked throughout. A quarter squat
        /// reads 0.33-0.40 and a half squat 0.53-0.63 from either placement, so
        /// 0.45 refuses the first and admits the second, with 0.05-0.08 to spare
        /// on each side - not much, and since the hips barely care where the
        /// phone is, footage of one quarter squat and one half squat will pin it.
        /// This is the gate that catches a quarter squat from a floor-level
        /// phone, where perspective has already compressed the gap towards a
        /// passing reading.
        let minHipDrop: Double = 0.45
        /// Standing: hips at least this far above the knees. Standing reads about
        /// 1.05-1.2 from any placement, since hips and knees are the same distance
        /// from the lens; 0.75 leaves room for a stocky build or a slight crouch
        /// and is still far above any half squat. Guess.
        let standingGap: Double = 0.75
        /// Standing still, joint jitter on a body a fifth of the frame tall is a
        /// few hundredths of a shoulder width per joint; 0.15 on both signals is
        /// several times that and far under the smallest countable travel. Any
        /// step, turn or shuffle exceeds it, which is the point. Guesses, and the
        /// HUD's `gap` and `hip` at rest will say by how much.
        let stillGapRange: Double = 0.15
        let stillHipRange: Double = 0.15
        /// Someone tiring on squats still stands up between reps - the standing
        /// gap is anatomy, not effort - so the top is carried forward far less
        /// generously than the elbow's 15 degrees. A third of the ordinary
        /// travel, matching the push-up proportion. Guess.
        let topCarry: Double = 0.15
        /// Shoulder width as a share of frame height, past which the knees leave
        /// the bottom of the frame at the bottom of the rep. At two metres the
        /// shoulders are about 0.14 of the frame's height; at one metre about
        /// 0.28, and the knees are already gone from a floor-level phone. Set
        /// high rather than low because this hint nags every frame it is true,
        /// and a nag about a distance the user has already got right is the kind
        /// of thing that makes the counter look broken. Guess.
        let tooCloseWidth: Double = 0.35

        return Movement(
            kind: .squat,
            // The knees are the joint the gap cannot do without and the one a
            // small, distant body loses first; the hips Vision is sure of.
            lenientJoints: [.leftKnee, .rightKnee],
            trackSpan: 0.2,
            minTravel: minGapTravel,
            soloTravel: soloGapTravel,
            maxBottom: maxBottomGap,
            strongDropTravel: strongHipDrop,
            corroboratedTravel: corroboratedGapTravel,
            corroboratedBottom: corroboratedBottomGap,
            // No deep tier for squats: nothing here has been read off footage,
            // and a tier that relaxes the depth gate is the last thing to guess.
            deepDropTravel: .infinity,
            deepCorroboratedTravel: corroboratedGapTravel,
            deepCorroboratedBottom: corroboratedBottomGap,
            // A squat is filmed facing the camera whichever way you stand it, so
            // there is no better view to switch to and no second set of numbers.
            sideOnMinTravel: minGapTravel,
            sideOnMaxBottom: maxBottomGap,
            sideOnCorroboratedTravel: corroboratedGapTravel,
            sideOnCorroboratedBottom: corroboratedBottomGap,
            minDropTravel: minHipDrop,
            restingTop: standingGap,
            stillRange: stillGapRange,
            stillDropRange: stillHipRange,
            topCarry: topCarry,
            tooCloseWidth: tooCloseWidth,
            // Standing tall, a hair under the gap that says "not squatting yet",
            // so a body that vanishes upright is read the same way a push-up
            // that vanishes with straight arms is. Guess, like the rest of this
            // profile, and waiting on squat footage.
            blindDescentTop: standingGap - 0.05,
            // The legs are the rep. There is no separate cheat to check them for.
            checksKneeling: false,
            needSignalHint: "Rex needs to see your hips and knees. Step back so your whole body is in shot.",
            tooCloseHint: "Back up a little bit before continuing, so your legs stay in shot.",
            lostBodyHint: "Stand the phone up a few feet away, facing you, with your whole body in shot.",
            shallowHint: "Not deep enough - sit lower, thighs to parallel.",
            lockedHint: "Didn't get low enough - hips down to knee height.",
            noDropHint: "Hips didn't drop - sit down into it.",
            noReturnHint: "Stand all the way back up to count."
        )
    }()
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
            if missingBodyFrames == 0 { lostAt = now }
            missingBodyFrames += 1
            guard missingBodyFrames > 25 else { return }
            let hint = movement.lostBodyHint
            Task { @MainActor in
                guard self.phase == .counting else { return }
                self.tracking = .searching
                self.poseFrame = nil
                self.formHint = hint
                self.blocker = self.blocking(.noBody)
                self.disarm()
            }
            return
        }

        if missingBodyFrames > 0, let lost = lostAt {
            noteRecovery(gap: now.timeIntervalSince(lost))
        }
        lostAt = nil
        missingBodyFrames = 0
        lastPrimarySeen = reading.primary ?? lastPrimarySeen
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

/// One frame of body geometry, normalised with a top-left origin, ready to draw
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
