import Foundation

/// Today, out of a hundred.
///
/// One number people check, made of three they can act on. Everything else in
/// the app reports a quantity - minutes, reps, reaches - and a quantity only
/// means something once you know what it should have been. A score does that
/// arithmetic for the user, and it is the same arithmetic every day, so
/// yesterday and today can be compared without doing any of it yourself.
///
/// There is deliberately no Sleep factor, and it is the obvious fourth. Nothing
/// on this phone can tell us when somebody slept without asking for HealthKit,
/// and a factor that reads "no data" forever is worse than three that are real.
struct DailyScore {
    /// How much of today's screen-time goal is still unspent. The outcome the
    /// user actually signed up for.
    let focus: Int
    /// Movement done against a day's worth of sets. The effort they put in.
    let reps: Int
    /// Reaches for a guarded app that did not turn into an unlock. Not what they
    /// used or what they did, but how often they went to the phone and stopped -
    /// which is the habit itself, and invisible in the other two.
    let restraint: Int

    /// An equal third each, because weighting one of them would be a claim about
    /// which matters most, and the honest answer is that they are the same thing
    /// seen from three sides.
    var total: Int { (focus + reps + restraint) / 3 }

    /// A day counts as good above this. Not a pass mark shown to the user - it
    /// only decides the colour, and a number that turns red at 69 teaches people
    /// to resent it.
    static let good = 70

    static func make(model: AppModel, reaches: Int) -> DailyScore {
        DailyScore(
            focus: focusScore(used: model.todayScreenMinutes, goal: model.todayAllowance),
            reps: repsScore(done: model.todayReps, target: model.plan.repsPerUnlock * 3),
            restraint: restraintScore(reaches: reaches, unlocks: model.unlocksToday)
        )
    }

    private static func clamp(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 100).rounded())
    }

    /// Full marks for an untouched day, nothing once the goal is gone. Linear
    /// between, so the score moves while there is still something to protect
    /// rather than falling off a cliff at the end.
    private static func focusScore(used: Int, goal: Int) -> Int {
        guard goal > 0 else { return used == 0 ? 100 : 0 }
        return clamp(1 - Double(used) / Double(goal))
    }

    /// Three sets is a day's worth. Doing more does not push past a hundred -
    /// this is a score for a day, not a leaderboard, and a number that rewards
    /// overtraining is the wrong incentive in a fitness app for people who do not
    /// train.
    private static func repsScore(done: Int, target: Int) -> Int {
        guard target > 0 else { return done > 0 ? 100 : 0 }
        return clamp(Double(done) / Double(target))
    }

    /// A day with no reaches is a hundred rather than nothing to report: not
    /// having gone to the phone at all is the best version of this, and scoring
    /// it zero for lack of evidence would punish the exact behaviour being asked
    /// for.
    private static func restraintScore(reaches: Int, unlocks: Int) -> Int {
        guard reaches > 0 else { return 100 }
        return clamp(1 - Double(min(unlocks, reaches)) / Double(reaches))
    }
}
