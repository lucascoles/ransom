import Foundation

// MARK: - Onboarding answers

enum Gender: String, CaseIterable, Codable, Identifiable {
    case female, male, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .female: return "Female"
        case .male:   return "Male"
        case .other:  return "Other"
        }
    }
}

/// The apps people name when asked what eats their day. Used before we ask for the
/// real Screen Time permission, so the flow stays friendly up front.
enum DistractingApp: String, CaseIterable, Codable, Identifiable {
    case instagram, tiktok, youtube, x, reddit, snapchat, facebook, games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok:    return "TikTok"
        case .youtube:   return "YouTube"
        case .x:         return "X"
        case .reddit:    return "Reddit"
        case .snapchat:  return "Snapchat"
        case .facebook:  return "Facebook"
        case .games:     return "Games"
        }
    }

    var emoji: String {
        switch self {
        case .instagram: return "📸"
        case .tiktok:    return "🎵"
        case .youtube:   return "▶️"
        case .x:         return "🐦"
        case .reddit:    return "👽"
        case .snapchat:  return "👻"
        case .facebook:  return "📘"
        case .games:     return "🎮"
        }
    }
}

enum ScrollLoad: String, CaseIterable, Codable, Identifiable {
    case light, medium, heavy, extreme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:   return "Under 1 hour"
        case .medium:  return "1–2 hours"
        case .heavy:   return "2–4 hours"
        case .extreme: return "4+ hours"
        }
    }

    /// Midpoint hours per day, used for the "here's what that costs you" reveal.
    var hoursPerDay: Double {
        switch self {
        case .light:   return 0.7
        case .medium:  return 1.5
        case .heavy:   return 3.0
        case .extreme: return 5.0
        }
    }

    /// How many unlocks a day the plan should expect.
    var expectedUnlocks: Int {
        switch self {
        case .light:   return 3
        case .medium:  return 5
        case .heavy:   return 8
        case .extreme: return 12
        }
    }

    var daysPerYear: Int { Int((hoursPerDay * 365) / 24) }
}

enum TimeOfDay: String, CaseIterable, Codable, Identifiable {
    case morning, midday, evening, lateNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:   return "First thing in the morning"
        case .midday:    return "Around lunch"
        case .evening:   return "After work"
        case .lateNight: return "Late at night in bed"
        }
    }

    /// Compact label for the chip row on the hours screen.
    var shortTitle: String {
        switch self {
        case .morning:   return "Mornings"
        case .midday:    return "Lunch"
        case .evening:   return "After work"
        case .lateNight: return "Late night"
        }
    }

    var emoji: String {
        switch self {
        case .morning:   return "🌅"
        case .midday:    return "🥪"
        case .evening:   return "🌆"
        case .lateNight: return "🌙"
        }
    }
}

enum ReferralSource: String, CaseIterable, Codable, Identifiable {
    case tiktok, instagram, friend, appStore, youtube, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok:    return "TikTok"
        case .instagram: return "Instagram"
        case .friend:    return "A friend"
        case .appStore:  return "App Store"
        case .youtube:   return "YouTube"
        case .other:     return "Somewhere else"
        }
    }

    var emoji: String {
        switch self {
        case .tiktok:    return "🎵"
        case .instagram: return "📸"
        case .friend:    return "🫂"
        case .appStore:  return "🍎"
        case .youtube:   return "▶️"
        case .other:     return "✨"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable {
    case metric, imperial
}

// MARK: - Profile

/// Everything the intake flow collects. Persisted as JSON, versioned by being
/// entirely optional-tolerant so a new field never breaks an existing install.
struct UserProfile: Codable, Equatable {
    var firstName: String = ""
    var gender: Gender?
    var age: Int = 24
    var units: UnitSystem = .imperial
    var heightCm: Double = 175
    var weightKg: Double = 72
    var fitnessLevel: FitnessLevel?
    var identity: Identity?
    var distractingApps: Set<DistractingApp> = []
    var scrollLoad: ScrollLoad?
    var exercises: Set<Exercise> = [.pushUps]
    var intensity: Intensity = .standard
    var peakTimes: Set<TimeOfDay> = []
    var referral: ReferralSource?
    var createdAt: Date = Date()

    var primaryExercise: Exercise {
        // Ordered by effort so the plan is quoted against the hardest thing they picked.
        exercises.sorted { $0.effortWeight > $1.effortWeight }.first ?? .pushUps
    }
}

// MARK: - Derived plan

/// The concrete numbers Rex enforces, derived from the intake answers.
struct RansomPlan: Equatable {
    var repsPerUnlock: Int
    var minutesPerUnlock: Int
    var dailyRepGoal: Int
    var exercise: Exercise
    /// Unlocks a day the plan expects, from the user's stated hours.
    var expectedUnlocksPerDay: Int
    /// Minutes of scrolling we expect the plan to remove per day.
    var projectedMinutesSavedPerDay: Int

    /// Reps this year at the user's own stated habit, under the real tariff.
    ///
    /// Deliberately computed rather than written: three separate reviewers quoted
    /// 20,000, 15,000 and 17,000 for this figure and the true range across plans is
    /// 12,775 to 98,550. A round invented number sitting next to the computed
    /// days-saved figure discredits both.
    var projectedRepsPerYear: Int {
        let unlocks = (0..<expectedUnlocksPerDay).reduce(0) { total, index in
            total + Tariff.quote(base: repsPerUnlock, unlocksToday: index,
                                 nightSurchargeEnabled: false).reps
        }
        return unlocks * 365
    }

    /// Rounded the way a person would say it out loud, never down.
    var projectedRepsRounded: Int {
        let value = projectedRepsPerYear
        let step = value >= 10_000 ? 1_000 : 500
        return Int((Double(value) / Double(step)).rounded()) * step
    }

    static func make(from profile: UserProfile) -> RansomPlan {
        let exercise = profile.primaryExercise
        let level = profile.fitnessLevel ?? .sometimes
        let load = profile.scrollLoad ?? .medium

        // Base target is in push-up equivalents; divide by effort weight so easier
        // movements ask for proportionally more reps.
        let equivalents = Double(profile.intensity.baseReps) * level.multiplier
        let raw = equivalents / exercise.effortWeight
        let reps = max(3, Int((raw / 1).rounded()))

        let minutes = profile.intensity.minutesGranted
        let dailyGoal = max(reps, reps * max(2, load.expectedUnlocks / 2))

        // Gated scrolling typically trims roughly a third of an unmanaged session.
        let savedPerDay = Int(load.hoursPerDay * 60 * 0.35)

        return RansomPlan(
            repsPerUnlock: reps,
            minutesPerUnlock: minutes,
            dailyRepGoal: dailyGoal,
            exercise: exercise,
            expectedUnlocksPerDay: load.expectedUnlocks,
            projectedMinutesSavedPerDay: savedPerDay
        )
    }
}

// MARK: - Activity

/// One completed set. The full history is the app's memory.
struct WorkoutRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var exercise: Exercise
    var reps: Int
    var durationSeconds: Int
    var minutesGranted: Int
    /// The app that triggered the set, when it came from a shield tap.
    var trigger: String?

    var calories: Double { Double(reps) * exercise.caloriesPerRep }
}
