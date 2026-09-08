import Foundation

/// The movements Rex can ask for. Each one knows how it is measured on device.
/// Three, deliberately. Push-ups and squats are the two movements the pose
/// counter measures reliably — both are a single joint angle sweeping through a
/// wide arc, square to the camera. Steps need no camera at all: the phone has
/// been counting them all day anyway. Jumping jacks, sit-ups and high knees were
/// dropped because none of them could be counted honestly, and a rep that can be
/// faked is worse than a movement that isn't offered.
public enum Exercise: String, CaseIterable, Codable, Identifiable, Sendable {
    case pushUps
    case squats
    case steps

    public var id: String { rawValue }

    /// What the pickers offer.
    ///
    /// Steps were withheld for a while, because the phone counts them whether or
    /// not anybody is trying and uncapped they fund an evening's scrolling from
    /// an ordinary day of walking about. `RansomPlan.stepMinutesCap` is what made
    /// them safe to offer: the first ten thousand steps pay, and no more.
    public static var selectable: [Exercise] { [.pushUps, .squats, .steps] }

    public var title: String {
        switch self {
        case .pushUps: return "Push-ups"
        case .squats:  return "Squats"
        case .steps:   return "Steps"
        }
    }

    public var shortTitle: String {
        switch self {
        case .pushUps: return "Push-ups"
        case .squats:  return "Squats"
        case .steps:   return "Steps"
        }
    }

    /// What one of them is called. Steps are counted, never "done in a set".
    public var unitLabel: String {
        switch self {
        case .pushUps, .squats: return "reps"
        case .steps:            return "steps"
        }
    }

    /// Steps accumulate in the background from the phone's own pedometer; the
    /// other two are earned in a set in front of the camera. Nearly every screen
    /// that behaves differently for steps branches on this.
    public var isPassive: Bool { self == .steps }

    /// The challenge name, matching how these read as programmes rather than
    /// exercises: "Push-up to Scroll".
    public var challengeTitle: String {
        switch self {
        case .pushUps: return "Push-up to Scroll"
        case .squats:  return "Squat to Scroll"
        case .steps:   return "Step to Scroll"
        }
    }

    public var symbol: String {
        switch self {
        // Not an SF Symbol. Apple ships no push-up - the nearest candidates are
        // a lunge and a sit-up - so this names an imageset. `ExerciseIcon`
        // resolves bundled art before system symbols.
        case .pushUps: return "figure.pushup"
        case .squats:  return "figure.cross.training"
        case .steps:   return "figure.walk"
        }
    }

    /// What the movement is for, in one line, for the picker. The setup cues
    /// below tell you where to put the phone, which is the wrong thing to read
    /// while you're still deciding whether you want to do squats at all.
    public var pitch: String {
        switch self {
        case .pushUps: return "The classic. Chest, arms and core."
        case .squats:  return "Legs and glutes. No floor needed."
        case .steps:   return "Your phone already counts them. Capped, so it can't be your only move."
        }
    }

    /// Copy shown while the movement is being counted.
    public var coachingCue: String {
        switch self {
        case .pushUps: return "Chest toward the floor, then all the way back up."
        case .squats:  return "Hips back, chest tall, thighs to parallel."
        case .steps:   return "Keep walking. Every step is banking minutes."
        }
    }

    /// Setup copy for the camera counter. The sensor cues above tell you to put
    /// the phone under your chest or in your pocket, which is exactly where the
    /// camera can see nothing — so the camera path needs its own instructions.
    public var cameraCue: String {
        switch self {
        case .pushUps: return "Prop the phone against a wall to your side, a few feet away, so your whole body is in shot."
        case .squats:  return "Stand the phone up a few feet away, facing you."
        case .steps:   return "Nothing to set up. Your phone is already counting."
        }
    }

    /// What the camera counter is waiting for before it arms. It arms on
    /// stillness at the top of a rep, and "the top" is a different posture per
    /// movement: a plank with straight arms, or standing tall. Telling a
    /// squatter to straighten their arms would have them checking the wrong limb.
    public var armingCue: String {
        switch self {
        case .pushUps: return "Hold still at the top, arms straight, and Rex will start counting."
        case .squats:  return "Stand tall and still, facing the phone, and Rex will start counting."
        case .steps:   return "Nothing to set up. Your phone is already counting."
        }
    }

    /// How the rep detector should read the sensors for this movement.
    public var sensing: SensingMode {
        switch self {
        case .pushUps: return .proximity
        case .squats:  return .tilt
        case .steps:   return .pedometer
        }
    }

    /// Relative effort, used only to order movements: the plan is quoted against
    /// the hardest thing the user picked, and Home lists the harder movement
    /// first. Steps sit at the bottom so a walking-only profile still prices
    /// its sets in a camera movement.
    ///
    /// It no longer prices anything. Set sizes used to be derived from it
    /// (push-ups divided by the weight), which gave a Chill squat set of 6.25
    /// and a Standard one of 12.5, rounded to numbers nobody would choose. The
    /// rep table lives on `Intensity` now, one whole number per movement per tier.
    public var effortWeight: Double {
        switch self {
        case .pushUps: return 1.0
        case .squats:  return 0.8
        case .steps:   return 0.02
        }
    }

    /// The bodyweight the per-rep figures below are quoted for.
    ///
    /// Push-ups and squats move your own body, so what a rep costs scales with
    /// how much of you there is. These numbers describe somebody of this weight;
    /// `WorkoutRecord.calories(forWeightKg:)` scales them to the actual user,
    /// which is the only reason the intake screen is entitled to ask.
    public static let referenceWeightKg: Double = 72

    /// Rough calories burned per rep at `referenceWeightKg`. Used for the stats
    /// screen, and an estimate rather than a measurement.
    public var caloriesPerRep: Double {
        switch self {
        case .pushUps: return 0.5
        case .squats:  return 0.4
        case .steps:   return 0.04
        }
    }

    public enum SensingMode: Sendable {
        /// Proximity sensor: face approaches and leaves the screen.
        case proximity
        /// Accelerometer impact peaks (landings).
        case impact
        /// Device attitude oscillation (pitch sweeps).
        case tilt
        /// Counted by the phone all day, with no session to run.
        case pedometer
    }
}

/// How hard Rex pushes. The tier sets how big one set is, and nothing else.
///
/// Every tier pays the same minutes. Chill used to pay 20 minutes for 5
/// push-ups and Beast 10 for 20, so the easy tier was rewarded twice over:
/// fewer reps, and more time for them. The size of the set is the whole
/// difference now, which is also the only part a person can feel.
public enum Intensity: String, CaseIterable, Codable, Identifiable, Sendable, Comparable {
    case chill
    case standard
    case beast

    public var id: String { rawValue }

    /// Chill < Standard < Beast. Settings refuses a move down this order while
    /// a run is committed, and compares tiers rather than rep counts so the
    /// rule holds in whichever movement the user is quoted in.
    public static func < (lhs: Intensity, rhs: Intensity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int { Intensity.allCases.firstIndex(of: self) ?? 0 }

    public var title: String {
        switch self {
        case .chill:    return "Chill"
        case .standard: return "Standard"
        case .beast:    return "Beast mode"
        }
    }

    public var blurb: String {
        switch self {
        // One line each. Two sentences wrapped onto a second line on every card,
        // and the number underneath is the part that actually decides it.
        //
        // No promise about time in any of them. "Easy sets, more time" was true
        // when Chill paid 20 minutes; every tier pays the same now, and the line
        // underneath says so with the real figure.
        case .chill:    return "Small sets. An easy way in."
        case .standard: return "Most people start here."
        case .beast:    return "Big sets. You'll feel it."
        }
    }

    public var symbol: String {
        switch self {
        case .chill:    return "leaf.fill"
        case .standard: return "flame.fill"
        case .beast:    return "bolt.fill"
        }
    }

    /// One set, in whichever movement is asked. Whole numbers, set by hand.
    ///
    /// Each movement gets its own column rather than a push-up figure divided
    /// by a weight, because the division produced sets of six and thirteen
    /// squats, and a set size is a number the user has to be able to say out
    /// loud and remember.
    ///
    /// Push-ups: 5 / 10 / 25. Standard stays at ten because it is the default
    /// and ten strict push-ups is already at the edge of what a sedentary adult
    /// manages in one go; the camera refuses knee push-ups, so a bigger default
    /// fails people on their first paid set, which is where they churn. Chill is
    /// the five the intake just had them do. Beast went up from twenty: with
    /// every tier paying the same minutes it had quietly become a third cheaper
    /// per minute than before, and Beast is the one tier picked on purpose to
    /// be hard. At a 4-hour baseline aiming at the suggested goal that is about
    /// ten sets a day, so 50 / 100 / 250 push-ups if every minute is bought.
    ///
    /// Squats: twice the push-ups. The old 0.8 weight came from calories, and
    /// calories are not difficulty; untrained people do about twice as many
    /// bodyweight squats as push-ups in a set, and "two squats to a push-up" is
    /// a rule a person can hold in their head.
    ///
    /// Steps: a set's worth at the flat per-minute rate, so the one figure ever
    /// quoted for walking is the one the bank honours.
    public func reps(for exercise: Exercise) -> Int {
        switch exercise {
        case .pushUps: return pushUps
        case .squats:  return squats
        case .steps:   return stepsPerMinute * minutesGranted
        }
    }

    /// Push-ups in one set.
    public var pushUps: Int {
        switch self {
        case .chill:    return 5
        case .standard: return 10
        case .beast:    return 25
        }
    }

    /// Squats in one set. See `reps(for:)` for why this is double the push-ups.
    public var squats: Int {
        switch self {
        case .chill:    return 10
        case .standard: return 20
        case .beast:    return 50
        }
    }

    /// Steps that buy one minute.
    ///
    /// Set directly rather than derived from `effortWeight` like the rep
    /// movements once were, because a step is not a small push-up: the weight
    /// that made squats price sensibly put a minute at thirty-three steps, which
    /// anyone clears walking to the kitchen. A hundred is the honest middle.
    ///
    /// Each one divides `RansomPlan.cappedSteps` exactly, so the daily ceiling
    /// quoted in copy is a round number of minutes (125 / 100 / 50) and a set's
    /// worth of walking is a round number of steps (1,200 / 1,500 / 3,000).
    /// Chill was 75, which made those 133 and 1,125.
    public var stepsPerMinute: Int {
        switch self {
        case .chill:    return 50
        case .standard: return 100
        case .beast:    return 200
        }
    }

    /// Minutes of scroll time banked by one completed set. The same on every
    /// tier, on purpose: the tier changes the size of the set, never the pay.
    public static let minutesPerSet = 15

    /// `minutesPerSet`, reachable from a tier so callers that read a per-tier
    /// figure still can. There is nothing per-tier about it any more.
    public var minutesGranted: Int { Intensity.minutesPerSet }
}



/// The one thing the user says they want back.
///
/// Replaces the old six-checkbox goals screen. It is quoted back on the plan screen
/// and on the paywall, which is the only thing that makes it worth a screen, so both
/// `statement` and `shortForm` have to stay short enough to sit inside a sentence.
public enum Identity: String, CaseIterable, Codable, Identifiable, Sendable {
    case stronger
    case eveningsBack
    case movesDaily
    case finishesThings

    public var id: String { rawValue }

    /// Always first person, always short. The user is picking a goal, not reading
    /// a paragraph about themselves.
    public var statement: String {
        switch self {
        case .stronger:       return "Get strong without a gym."
        case .eveningsBack:   return "Take my evenings back."
        case .movesDaily:     return "Move every day."
        case .finishesThings: return "Finish what I start."
        }
    }

    /// Second person, verb first, so the plan screen and the paywall can drop it
    /// straight into a sentence: "This is how you take your evenings back."
    public var shortForm: String {
        switch self {
        case .stronger:       return "get strong without a gym"
        case .eveningsBack:   return "take your evenings back"
        case .movesDaily:     return "move every day"
        case .finishesThings: return "finish what you start"
        }
    }

    public var emoji: String {
        switch self {
        case .stronger:       return "💪"
        case .eveningsBack:   return "🌙"
        case .movesDaily:     return "🏃"
        case .finishesThings: return "🎯"
        }
    }
}
