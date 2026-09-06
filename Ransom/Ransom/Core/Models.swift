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

/// The apps people name when asked what takes up their day. These are quick picks
/// shown before the Screen Time permission prompt, so the flow stays friendly up
/// front. Apple will not let a third-party app render another app's real icon
/// before the user has selected it in `FamilyActivityPicker`, so these carry emoji
/// stand-ins; the picker itself shows the real icons.
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
        case .x:         return "✖️"
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
        case .medium:  return "1-2 hours"
        case .heavy:   return "2-4 hours"
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

    /// The bucket a given number of minutes falls into. The exact figure is the
    /// real answer now; this exists so the handful of places still reading a
    /// bucket can't drift away from it.
    static func matching(minutes: Int) -> ScrollLoad {
        switch minutes {
        case ..<60:  return .light
        case ..<120: return .medium
        case ..<240: return .heavy
        default:     return .extreme
        }
    }
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
    var identity: Identity?
    var distractingApps: Set<DistractingApp> = []
    var scrollLoad: ScrollLoad?
    /// Their actual daily average, in minutes, when they read it off Screen Time
    /// rather than picking a bucket. Nil means they estimated.
    ///
    /// There is no public API that hands an app the phone's total screen time —
    /// Apple only lets it be *rendered* inside a DeviceActivityReport extension,
    /// never read as a number. So the exact figure can only come from the user
    /// typing what Settings shows them.
    var measuredDailyMinutes: Int?
    /// The daily ceiling they set for themselves, in minutes.
    var goalDailyMinutes: Int?
    /// How long they committed to the plan for, and when the clock started.
    /// Nil before the commitment step, and never cleared afterwards.
    /// Weekdays Ransom guards, as `Calendar` numbers with 1 = Sunday. Empty is
    /// every day, which is what every profile written before this decodes to.
    var activeDays: Set<Int> = []
    var commitmentDays: Int?
    var commitmentStartedAt: Date?
    var exercises: Set<Exercise> = [.pushUps]
    var intensity: Intensity = .standard
    var peakTimes: Set<TimeOfDay> = []
    var referral: ReferralSource?
    var createdAt: Date = Date()

    /// The benchmark everything is measured against: their own figure when they
    /// gave one, otherwise the midpoint of the bucket they picked.
    var baselineDailyMinutes: Int {
        if let measuredDailyMinutes, measuredDailyMinutes > 0 { return measuredDailyMinutes }
        return Int(((scrollLoad ?? .medium).hoursPerDay * 60).rounded())
    }

    /// What to put in front of them when they first set a goal. A third off is the
    /// same reduction the plan projects everywhere else, so the suggestion and the
    /// forecast can't contradict each other.
    var suggestedGoalMinutes: Int {
        max(10, Int((Double(baselineDailyMinutes) * 0.65 / 5).rounded()) * 5)
    }

    /// When the commitment runs out, if one was made.
    var commitmentEndsAt: Date? {
        guard let commitmentDays, let commitmentStartedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: commitmentDays, to: commitmentStartedAt)
    }

    /// True while the plan is locked. Settings reads this to decide whether the
    /// difficulty can be softened.
    var isCommitted: Bool {
        guard let commitmentEndsAt else { return false }
        return commitmentEndsAt > Date()
    }

    var commitmentDaysLeft: Int {
        guard let commitmentEndsAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: commitmentEndsAt).day ?? 0
        return max(0, days + 1)
    }

    /// What one set costs at a given tier, in this user's movement. Shown on
    /// every tier including the locked ones: a difficulty someone
    /// can't pick yet is exactly the one they most want the number for, since
    /// that's the decision they're weighing up.
    func setSize(at intensity: Intensity) -> Int {
        max(3, Int((Double(intensity.baseReps) / primaryExercise.effortWeight).rounded()))
    }

    /// "10 push-ups for 15 min", in the user's own movement.
    func setSummary(at intensity: Intensity) -> String {
        "\(setSize(at: intensity)) \(primaryExercise.shortTitle.lowercased()) for \(intensity.minutesGranted) min"
    }

    var primaryExercise: Exercise {
        // Ordered by effort so the plan is quoted against the hardest thing they picked.
        exercises.sorted { $0.effortWeight > $1.effortWeight }.first ?? .pushUps
    }

    /// A filled-in profile for screenshot runs, so screens that quote the plan
    /// back at the user have real answers to quote instead of defaults.
    /// Paired with `OnboardingStep.launchStep`; debug builds only.
    static var launchSeed: UserProfile? {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "RansomStartStep") != nil else { return nil }
        var profile = UserProfile()
        // `-RansomSeedName ""` captures the no-name states (Rex's greeting, the
        // unpersonalised plan title) that the default seed can never show.
        profile.firstName = UserDefaults.standard.string(forKey: "RansomSeedName") ?? "Sam"
        profile.identity = .stronger
        profile.distractingApps = [.instagram, .tiktok, .youtube, .reddit]
        profile.scrollLoad = .heavy
        profile.measuredDailyMinutes = 420
        profile.goalDailyMinutes = 275
        profile.commitmentDays = 5
        profile.commitmentStartedAt = Date()
        profile.exercises = [.pushUps, .squats]
        profile.peakTimes = [.evening, .lateNight]
        return profile
        #else
        return nil
        #endif
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
    /// The user's own stated daily hours, kept so projections and copy agree.
    var hoursPerDay: Double
    /// Steps to a minute, straight off the intensity rather than derived.
    var stepsPerMinute: Int
    /// The sentence they committed to in the intake, echoed back where it counts.
    var identity: Identity?

    /// How far the habit is expected to have shrunk once the plan settles: the gap
    /// between the hours they gave and the target they set, as a fraction of the
    /// hours. Profiles from before the goal step existed get the third the
    /// suggested goal is built from, so an old install still has a curve.
    var targetReduction: Double

    /// How much of the daily habit the plan is expected to remove by a given day,
    /// ramping to their target over four weeks.
    ///
    /// One curve serves every projection in the app. The plan screen's chart already
    /// promises screen time falls; an earlier version held unlocks flat forever and
    /// quoted 108,000 reps a year beside that same falling line. Arithmetically
    /// correct, internally contradictory, and not a number anyone believes.
    ///
    /// The curve ends on the user's own target, not a constant. With a fixed third
    /// the plan screen's chart landed on the goal only when the user kept the
    /// suggested one, and contradicted it the moment they dragged the slider.
    private func reduction(onDay day: Int) -> Double {
        targetReduction * min(1, Double(day) / 28)
    }

    /// Minutes earned by a given number of reps of a given movement.
    ///
    /// Everything is priced in push-up equivalents, so a squat is worth a little
    /// less than a push-up and a step a fraction of either — and all three pay into
    /// the same bank at the same rate per unit of effort.
    func minutesEarned(reps: Int, exercise: Exercise) -> Int {
        guard reps > 0 else { return 0 }
        // Steps are priced flat rather than in push-up equivalents. Rounded down,
        // so the app never pays for a minute that hasn't been walked.
        if exercise == .steps {
            guard stepsPerMinute > 0 else { return 0 }
            return reps / stepsPerMinute
        }
        guard repsPerUnlock > 0 else { return 0 }

        // Against this exercise's own target, not against push-up equivalents.
        //
        // `effortWeight` was being applied twice: once in `make`, which divides
        // the base reps by it to set `repsPerUnlock`, and again here, which
        // multiplied the reps back up. For the plan's own movement the two
        // almost cancel and the drift hides in the rounding - a standard squat
        // set paid 16 minutes for a 15-minute plan - and for any other movement
        // they do not cancel at all.
        //
        // One rule instead: a full set of whatever you are doing is worth
        // exactly `minutesPerUnlock`, and a part of a set is worth its share.
        let minutes = Double(reps) / Double(repsRequired(for: exercise)) * Double(minutesPerUnlock)
        return Int(minutes.rounded())
    }

    /// How many of `exercise` make one set, when the plan was priced for a
    /// possibly different movement. Squats are easier than push-ups, so it takes
    /// more of them; the ratio of the two weights is the whole conversion.
    func repsRequired(for exercise: Exercise) -> Int {
        guard exercise != .steps, exercise.effortWeight > 0 else { return max(1, repsPerUnlock) }
        guard exercise != self.exercise else { return max(1, repsPerUnlock) }
        let scaled = Double(repsPerUnlock) * self.exercise.effortWeight / exercise.effortWeight
        return max(3, Int(scaled.rounded()))
    }

    /// The amounts offered when spending from the bank.
    ///
    /// Steps of one set's worth, so spending is quoted in the same unit as
    /// earning: on Beast a set is ten minutes and the choices are 10/20/30, on
    /// Chill it's twenty and they're 20/40/60. Someone who has done three sets
    /// sees three sets' worth on offer, which needs no explaining.
    ///
    /// "All" is appended whenever the balance doesn't already land on a step, so
    /// there is always a way to spend the remainder rather than stranding four
    /// minutes nobody can reach.
    func spendOptions(banked: Int) -> [Int] {
        guard banked > 0, minutesPerUnlock > 0 else { return [] }
        var options = (1...3).map { $0 * minutesPerUnlock }.filter { $0 <= banked }
        if options.isEmpty { return [banked] }
        if !options.contains(banked) { options.append(banked) }
        return options
    }

    /// The same plan at a higher price, for a focus rule that is running.
    ///
    /// Only the cost moves. Minutes granted, the goal and every projection stay
    /// exactly where they were, because a rule is meant to make the phone more
    /// expensive for an hour, not to rewrite what the user signed up to.
    func scaled(by multiplier: Int) -> RansomPlan {
        guard multiplier > 1 else { return self }
        var scaled = self
        scaled.repsPerUnlock *= multiplier
        scaled.stepsPerMinute *= multiplier
        return scaled
    }

    /// The most a day's walking can be worth.
    ///
    /// Steps were withheld from the app for exactly this: the phone counts them
    /// whether or not anybody is trying, so uncapped they turn an ordinary day of
    /// walking about into an evening of scrolling, and the habit never has to
    /// change. Two sets' worth is the ceiling - enough that a genuine walk is
    /// recognised, not enough that anyone can live off it.
    var stepMinutesCap: Int { minutesPerUnlock * 2 }

    /// How many of a movement it takes to earn one minute. Quoted on the home
    /// screen so the exchange rate is never a mystery.
    func repsPerMinute(for exercise: Exercise) -> Int {
        if exercise == .steps { return stepsPerMinute }
        guard minutesPerUnlock > 0, exercise.effortWeight > 0 else { return 0 }
        let perMinute = Double(repsPerUnlock) / Double(minutesPerUnlock) / exercise.effortWeight
        return max(1, Int(perMinute.rounded()))
    }

    /// The ceiling for a given day: the user's own stated daily hours, less however
    /// much of the habit the curve expects to have removed by then.
    ///
    /// This is the number the whole app is actually for. Reps are the price of
    /// crossing it, not the point of the exercise — a user who paid 200 reps to
    /// scroll all evening has lost, however good the rep count looks.
    func dailyMinuteAllowance(onDay day: Int) -> Int {
        max(5, Int((hoursPerDay * 60 * (1 - reduction(onDay: day))).rounded()))
    }

    /// Reps paid across the first `days`, priced by the real tariff and discounted
    /// by the unlocks the tariff is expected to prevent.
    func projectedReps(overDays days: Int) -> Int {
        // One flat price per set now, so this is simply the unlocks the curve
        // expects times the rate. The old version summed an escalating tariff and
        // quoted eleven thousand push-ups a month; the same curve at a flat rate
        // gives a number a person might actually believe.
        var total = 0.0
        for day in 0..<days {
            let unlocks = Double(expectedUnlocksPerDay) * (1 - reduction(onDay: day))
            total += unlocks * Double(repsPerUnlock)
        }
        return Int(total.rounded())
    }

    /// Hours of scrolling the same curve expects to remove across the first `days`.
    func projectedHoursSaved(overDays days: Int) -> Double {
        (0..<days).reduce(0) { total, day in
            total + hoursPerDay * reduction(onDay: day)
        }
    }

    var firstWeekReps: Int { Self.round(projectedReps(overDays: 7)) }
    var firstMonthReps: Int { Self.round(projectedReps(overDays: 30)) }
    var firstMonthHoursSaved: Double { projectedHoursSaved(overDays: 30) }

    /// Rounded the way a person would say it out loud.
    private static func round(_ value: Int) -> Int {
        let step = value >= 10_000 ? 1_000 : (value >= 2_000 ? 100 : 50)
        return Int((Double(value) / Double(step)).rounded()) * step
    }

    static func make(from profile: UserProfile) -> RansomPlan {
        let exercise = profile.primaryExercise
        // The exact figure when there is one. A bucket midpoint tops out at five
        // hours, so every projection for a ten-hour-a-day user was quietly wrong.
        let dailyHours = Double(profile.baselineDailyMinutes) / 60

        // The tier is the whole answer.
        //
        // A self-reported fitness level used to scale this, so "Standard" meant ten
        // push-ups for one person and fourteen for another. It made the number
        // unexplainable ("why does mine say 14?") and it was a guess made once, on
        // day one, about something that changes as you get stronger - and the tier
        // is already there to be moved up when it does.
        let raw = Double(profile.intensity.baseReps) / exercise.effortWeight
        let reps = max(3, Int(raw.rounded()))

        let minutes = profile.intensity.minutesGranted
        let expectedUnlocks = max(2, Int((dailyHours * 2.5).rounded()))
        let dailyGoal = max(reps, reps * max(2, expectedUnlocks / 2))

        // The curve ends where they said they wanted to land. Without a goal (a
        // profile from before the goal step) it falls back to the third the
        // suggestion is built from, so nothing downstream has to special-case it.
        let targetReduction: Double
        if let goal = profile.goalDailyMinutes, profile.baselineDailyMinutes > 0 {
            targetReduction = min(1, max(0, 1 - Double(goal) / Double(profile.baselineDailyMinutes)))
        } else {
            targetReduction = 0.35
        }
        // Their hours minus their target, in minutes. Rounded rather than truncated
        // so it matches the difference the goal step showed them.
        let savedPerDay = Int((dailyHours * 60 * targetReduction).rounded())

        return RansomPlan(
            repsPerUnlock: reps,
            minutesPerUnlock: minutes,
            dailyRepGoal: dailyGoal,
            exercise: exercise,
            expectedUnlocksPerDay: expectedUnlocks,
            projectedMinutesSavedPerDay: savedPerDay,
            hoursPerDay: dailyHours,
            stepsPerMinute: profile.intensity.stepsPerMinute,
            identity: profile.identity,
            targetReduction: targetReduction
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
