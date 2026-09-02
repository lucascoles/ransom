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

enum Goal: String, CaseIterable, Codable, Identifiable {
    case lessScreenTime
    case getStronger
    case buildHabit
    case loseWeight
    case moreFocus
    case moveMore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lessScreenTime: return "Cut my screen time"
        case .getStronger:    return "Get stronger"
        case .buildHabit:     return "Build a daily habit"
        case .loseWeight:     return "Lose weight"
        case .moreFocus:      return "Focus better"
        case .moveMore:       return "Just move more"
        }
    }

    var emoji: String {
        switch self {
        case .lessScreenTime: return "📵"
        case .getStronger:    return "💪"
        case .buildHabit:     return "🔁"
        case .loseWeight:     return "🔥"
        case .moreFocus:      return "🎯"
        case .moveMore:       return "🏃"
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
    var goals: Set<Goal> = []
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
struct ReppPlan: Equatable {
    var repsPerUnlock: Int
    var minutesPerUnlock: Int
    var dailyRepGoal: Int
    var exercise: Exercise
    /// Minutes of scrolling we expect the plan to remove per day.
    var projectedMinutesSavedPerDay: Int

    static func make(from profile: UserProfile) -> ReppPlan {
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

        return ReppPlan(
            repsPerUnlock: reps,
            minutesPerUnlock: minutes,
            dailyRepGoal: dailyGoal,
            exercise: exercise,
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
