import Foundation

/// The movements Rex can ask for. Each one knows how it is measured on device.
public enum Exercise: String, CaseIterable, Codable, Identifiable, Sendable {
    case pushUps
    case jumpingJacks
    case squats
    case sitUps
    case highKnees

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pushUps:      return "Push-ups"
        case .jumpingJacks: return "Jumping jacks"
        case .squats:       return "Squats"
        case .sitUps:       return "Sit-ups"
        case .highKnees:    return "High knees"
        }
    }

    public var shortTitle: String {
        switch self {
        case .pushUps:      return "Push-ups"
        case .jumpingJacks: return "Jacks"
        case .squats:       return "Squats"
        case .sitUps:       return "Sit-ups"
        case .highKnees:    return "Knees"
        }
    }

    public var symbol: String {
        switch self {
        case .pushUps:      return "figure.strengthtraining.functional"
        case .jumpingJacks: return "figure.mixed.cardio"
        case .squats:       return "figure.cross.training"
        case .sitUps:       return "figure.core.training"
        case .highKnees:    return "figure.highintensity.intervaltraining"
        }
    }

    /// Copy shown while the movement is being counted.
    public var coachingCue: String {
        switch self {
        case .pushUps:      return "Phone on the floor. Chest to the screen, then all the way up."
        case .jumpingJacks: return "Phone in your hand or pocket. Big arms, light feet."
        case .squats:       return "Phone in your pocket. Hips back, chest tall."
        case .sitUps:       return "Phone on your chest. Shoulders off the floor, then down."
        case .highKnees:    return "Phone in your hand. Knees to hip height, keep the pace."
        }
    }

    /// How the rep detector should read the sensors for this movement.
    public var sensing: SensingMode {
        switch self {
        case .pushUps:                    return .proximity
        case .jumpingJacks, .highKnees:   return .impact
        case .squats, .sitUps:            return .tilt
        }
    }

    /// Relative effort, used to scale rep targets so 1 push-up ≈ 2 jumping jacks.
    public var effortWeight: Double {
        switch self {
        case .pushUps:      return 1.0
        case .squats:       return 0.8
        case .sitUps:       return 0.7
        case .jumpingJacks: return 0.5
        case .highKnees:    return 0.4
        }
    }

    /// Rough calories burned per rep for an average adult. Used for the stats screen.
    public var caloriesPerRep: Double {
        switch self {
        case .pushUps:      return 0.5
        case .squats:       return 0.4
        case .sitUps:       return 0.3
        case .jumpingJacks: return 0.2
        case .highKnees:    return 0.15
        }
    }

    public enum SensingMode: Sendable {
        /// Proximity sensor: face approaches and leaves the screen.
        case proximity
        /// Accelerometer impact peaks (landings).
        case impact
        /// Device attitude oscillation (pitch sweeps).
        case tilt
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
        case .chill:    return "Easing in. Short sets, generous scroll time."
        case .standard: return "The sweet spot. Most people start here."
        case .beast:    return "Rex shows no mercy. Earn every single minute."
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

    /// Minutes of scroll time granted per completed set.
    public var minutesGranted: Int {
        switch self {
        case .chill:    return 20
        case .standard: return 15
        case .beast:    return 10
        }
    }
}

/// Self-reported baseline fitness, nudges the rep target up or down.
public enum FitnessLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case rarely
    case sometimes
    case often

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rarely:    return "0–2 times a week"
        case .sometimes: return "3–5 times a week"
        case .often:     return "6+ times a week"
        }
    }

    public var subtitle: String {
        switch self {
        case .rarely:    return "We'll start you gently."
        case .sometimes: return "You've got a base to build on."
        case .often:     return "Rex will make it count."
        }
    }

    public var multiplier: Double {
        switch self {
        case .rarely:    return 0.7
        case .sometimes: return 1.0
        case .often:     return 1.4
        }
    }
}
