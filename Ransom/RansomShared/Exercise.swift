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
    /// them safe to offer: a day's walking is worth two sets and no more.
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
        case .pushUps: return "figure.strengthtraining.functional"
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
        case .steps:   return "Your phone counts them already. Capped, so it tops you up rather than covering the day."
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

    /// Relative effort, used to scale rep targets so a squat asks for a few more
    /// reps than a push-up and a walk asks for a great many more steps.
    public var effortWeight: Double {
        switch self {
        case .pushUps: return 1.0
        case .squats:  return 0.8
        // A step is a fraction of a push-up, so a set-sized target becomes a
        // walk-sized one: ten push-ups' worth is five hundred steps.
        case .steps:   return 0.02
        }
    }

    /// Rough calories burned per rep for an average adult. Used for the stats screen.
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

/// How hard Rex pushes. Drives reps required and minutes granted per unlock.
public enum Intensity: String, CaseIterable, Codable, Identifiable, Sendable {
    case chill
    case standard
    case beast

    public var id: String { rawValue }

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
        case .chill:    return "Easy sets, more time."
        case .standard: return "Most people start here."
        case .beast:    return "Big sets, less time."
        }
    }

    public var symbol: String {
        switch self {
        case .chill:    return "leaf.fill"
        case .standard: return "flame.fill"
        case .beast:    return "bolt.fill"
        }
    }

    /// Base push-up equivalent required for one unlock.
    public var baseReps: Int {
        switch self {
        case .chill:    return 5
        case .standard: return 10
        case .beast:    return 20
        }
    }

    /// Steps that buy one minute.
    ///
    /// Set directly rather than derived from `effortWeight` like the rep
    /// movements, because a step is not a small push-up: the weight that made
    /// squats price sensibly put a minute at thirty-three steps, which anyone
    /// clears walking to the kitchen. A hundred is the honest middle.
    public var stepsPerMinute: Int {
        switch self {
        case .chill:    return 75
        case .standard: return 100
        case .beast:    return 200
        }
    }

    /// Minutes of scroll time granted per completed set.
    public var minutesGranted: Int {
        switch self {
        case .chill:    return 20
        case .standard: return 15
        case .beast:    return 10
        }
    }
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
