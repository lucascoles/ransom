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
    /// Weekdays Ransom guards, as `Calendar` numbers with 1 = Sunday. Empty is
    /// every day, which is what every profile written before this decodes to.
    var activeDays: Set<Int> = []
    /// A quieter week asked for during a run, waiting for its date. Nil when
    /// nothing is waiting, which is also what every profile written before days
    /// off could wait decodes to. Read and written through `schedule`.
    var pendingActiveDays: Set<Int>?
    var pendingActiveDaysFrom: Date?
    /// How long they committed to the plan for, and when the clock started.
    /// Nil before the commitment step, and never cleared afterwards.
    var commitmentDays: Int?
    var commitmentStartedAt: Date?
    var exercises: Set<Exercise> = [.pushUps]
    var intensity: Intensity = .standard
    var peakTimes: Set<TimeOfDay> = []
    var referral: ReferralSource?
    var createdAt: Date = Date()

    /// Whether `baselineDailyMinutes` was answered about the whole phone.
    ///
    /// Nil in every profile written before the benchmark moved from the guarded
    /// apps to the whole device, and nil is the point: those users answered a
    /// different question. Their number counted the handful of apps they picked,
    /// and what gets measured now is everything, so subtracting one from the
    /// other says they have blown a budget they never set.
    ///
    /// Optional rather than a defaulted `Bool` because the synthesised decoder
    /// only falls back to nil for optionals - a non-optional missing key throws,
    /// and a profile that fails to decode is a user who loses their whole plan
    /// on upgrade. A fresh profile gets `true` from the memberwise default,
    /// which is every profile built by a version that asks the new question.
    var baselineIsWholePhone: Bool? = true

    /// Whether the baseline can honestly be compared against what is measured
    /// today. Nothing is invented when it can't - the comparisons go quiet until
    /// the user answers the new question.
    var hasComparableBaseline: Bool { baselineIsWholePhone == true }

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

    /// The days on duty as one value, pending week included. The three stored
    /// fields stay separate so an old profile decodes; this is the shape
    /// everything reads and writes.
    var schedule: WeekSchedule {
        get {
            WeekSchedule(days: activeDays, pendingDays: pendingActiveDays, pendingFrom: pendingActiveDaysFrom)
        }
        set {
            activeDays = newValue.days
            pendingActiveDays = newValue.pendingDays
            pendingActiveDaysFrom = newValue.pendingFrom
        }
    }

    /// When a change to the days takes effect. Built from the run and the
    /// profile's age; see `ScheduleChangeRule` for the rule itself.
    ///
    /// Anchored to `createdAt` rather than the run's start on purpose: extending
    /// the run resets `commitmentStartedAt`, and a grace that came back with it
    /// would make "extend, then take today off" a two-tap escape.
    var scheduleRule: ScheduleChangeRule {
        ScheduleChangeRule(
            lockEndsAt: commitmentEndsAt,
            graceEndsAt: ScheduleChangeRule.graceEnd(forProfileCreatedAt: createdAt)
        )
    }

    /// What one set costs at a given tier, in this user's movement. Shown on
    /// every tier including the locked ones: a difficulty someone
    /// can't pick yet is exactly the one they most want the number for, since
    /// that's the decision they're weighing up.
    ///
    /// Straight off the tier's table. Dividing push-ups by `effortWeight` here
    /// quoted a walking-only profile "500 steps for 15 min" while the bank paid
    /// a minute per hundred; the table's steps column is the bank's own figure.
    func setSize(at intensity: Intensity) -> Int {
        intensity.reps(for: primaryExercise)
    }

    /// "10 push-ups for 15 min", in the user's own movement.
    func setSummary(at intensity: Intensity) -> String {
        "\(setSize(at: intensity).formatted()) \(primaryExercise.shortTitle.lowercased()) for \(intensity.minutesGranted) min"
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
    /// The tier every set is priced from. Kept rather than flattened into a
    /// single rep count, because Home lets the user swap movements mid-day and
    /// each movement has its own column in the tier's table.
    var intensity: Intensity
    /// How many times over the tier's table a set costs right now. One
    /// normally; a running focus rule sets it higher via `scaled(by:)`.
    var costMultiplier: Int = 1
    var minutesPerUnlock: Int
    var dailyRepGoal: Int
    var exercise: Exercise

    /// One set of the movement the plan counts in. Derived, so a rule that
    /// doubles the price can never leave this and `repsRequired(for:)` quoting
    /// two different numbers for the same set.
    var repsPerUnlock: Int { repsRequired(for: repMovement) }
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
    ///
    /// An S-curve rather than a straight ramp: a slow first few days while the
    /// habit is still the habit, the steep part in weeks two and three, then a
    /// settle onto the target. That is the shape a habit actually changes in,
    /// and it is what the plan screen's chart draws. Smoothstep integrates to
    /// exactly one half over the ramp, the same as the straight line did, so
    /// the month-one hours quoted on the plan and the paywall did not move.
    private func reduction(onDay day: Int) -> Double {
        let t = min(1, max(0, Double(day) / Double(RansomPlan.rampDays)))
        return targetReduction * t * t * (3 - 2 * t)
    }

    /// How long the curve takes to reach the target. The plan screen quotes the
    /// calendar date this many days out.
    static let rampDays = 28

    /// Minutes earned by a given number of reps of a given movement.
    ///
    /// A full set of any movement is worth the same minutes; the tier's table
    /// says how many of each movement make a set, and all three pay into the
    /// same bank.
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

    /// How many of `exercise` make one set. Read off the tier's own table for
    /// that movement, times whatever a running rule has multiplied the price by.
    ///
    /// This used to convert the plan's push-up count through the ratio of two
    /// effort weights, which is where the sets of six and thirteen squats came
    /// from. The table has a whole number for every movement, so there is no
    /// conversion left to do.
    func repsRequired(for exercise: Exercise) -> Int {
        // Steps are priced from `stepsPerMinute`, which `scaled(by:)` has already
        // multiplied, rather than from the table times the multiplier: the only
        // figure that can be quoted for a walk is the one the bank will honour,
        // and the bank pays per minute, not per set.
        if exercise == .steps { return max(1, stepsPerMinute * minutesPerUnlock) }
        return max(1, intensity.reps(for: exercise) * max(1, costMultiplier))
    }

    /// The movement `repsPerUnlock` is counted in - the plan's own, unless that is
    /// walking, which has no rep target to count.
    var repMovement: Exercise { exercise.isPassive ? .pushUps : exercise }

    /// One set of the plan's own movement, in whatever unit that movement uses.
    ///
    /// Every screen that quotes "N <movement> unlocks M minutes" has to go through
    /// this rather than reading `repsPerUnlock` beside `exercise`, because for a
    /// walking plan those two are in different units and the sentence they made
    /// was false.
    var setTarget: Int { repsRequired(for: exercise) }

    /// The amounts offered when spending from the bank.
    ///
    /// Fixed steps, and the first one is deliberately small.
    ///
    /// These used to be multiples of one set's worth, so the smallest thing you
    /// could buy was a whole unlock: 15 minutes on Standard, 20 on Chill. That
    /// quoted spending in the same unit as earning, which reads tidily and works
    /// against the entire product. Somebody who wants to answer one message has
    /// to buy a quarter of an hour, and a quarter of an hour of Instagram is not
    /// what they came for. The floor on the cheapest purchase was setting the
    /// floor on the session.
    ///
    /// Five is enough to reply to something and not enough to settle in.
    ///
    /// "All" is still appended whenever the balance doesn't already land on a
    /// step, so there is always a way to spend the remainder rather than
    /// stranding four minutes nobody can reach.
    static let spendSteps = [5, 15, 30]

    func spendOptions(banked: Int) -> [Int] {
        guard banked > 0 else { return [] }
        var options = RansomPlan.spendSteps.filter { $0 <= banked }
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
        scaled.costMultiplier = costMultiplier * multiplier
        scaled.stepsPerMinute *= multiplier
        return scaled
    }

    /// The most a day's walking can be worth: the first ten thousand steps of it.
    ///
    /// Steps were withheld from the app for exactly one reason: the phone counts
    /// them whether or not anybody is trying, so uncapped they turn an ordinary
    /// day of walking about into an evening of scrolling and the habit never has
    /// to change. So there is still a ceiling.
    ///
    /// Where it sits is the part that had to change. It used to be two unlocks'
    /// worth - thirty minutes, about three thousand steps on a standard plan -
    /// which is reached before lunch, and a cap you hit before lunch stops being
    /// a guard rail and starts being a reason not to walk any further. Ten
    /// thousand is the figure people already carry in their heads as a day's
    /// walking, so the ceiling now sits at the far end of a good day rather than
    /// in the middle of an ordinary one.
    var stepMinutesCap: Int {
        guard stepsPerMinute > 0 else { return 0 }
        return RansomPlan.cappedSteps / stepsPerMinute
    }

    /// A day's walking, as everybody already counts it.
    static let cappedSteps = 10_000

    /// How many of a movement it takes to earn one minute. Quoted on the home
    /// screen so the exchange rate is never a mystery.
    func repsPerMinute(for exercise: Exercise) -> Int {
        if exercise == .steps { return stepsPerMinute }
        guard minutesPerUnlock > 0 else { return 0 }
        let perMinute = Double(repsRequired(for: exercise)) / Double(minutesPerUnlock)
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
            total += unlocks * Double(setTarget)
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
        //
        // Counted in a camera movement even when the plan's own movement is
        // walking. A step is not a small push-up, and running one through the
        // rep arithmetic once produced a plan quoting five hundred steps for a
        // fifteen-minute unlock while the bank paid a minute per hundred - the
        // same walk described two ways, three times apart. Steps are priced off
        // their own flat rate in `repsRequired(for:)` instead.
        let repMovement = exercise.isPassive ? Exercise.pushUps : exercise
        let reps = profile.intensity.reps(for: repMovement)

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
            intensity: profile.intensity,
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

    /// Estimated burn for this set, scaled to the user's own bodyweight.
    ///
    /// Takes the weight rather than storing it, deliberately. A weight copied
    /// onto every record would be a second source of truth that silently goes
    /// stale the day somebody updates their profile, and it would put body data
    /// into the workout history where nothing else needs it.
    ///
    /// A missing or implausible weight falls back to the reference figure
    /// instead of producing a zero: an unanswered question should give an
    /// average estimate, not claim the set burned nothing.
    func calories(forWeightKg weightKg: Double) -> Double {
        let weight = (weightKg > 20 && weightKg < 400) ? weightKg : Exercise.referenceWeightKg
        return Double(reps) * exercise.caloriesPerRep * (weight / Exercise.referenceWeightKg)
    }
}
