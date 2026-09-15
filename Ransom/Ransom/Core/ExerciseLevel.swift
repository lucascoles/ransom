import Foundation

/// A level per movement, earned by lifetime volume.
///
/// The ladder is steep at the bottom on purpose. Level one is a single set, and
/// the first few land inside the first week, because a progress bar that sits on
/// zero for a month teaches nobody that it moves. After that the gaps widen:
/// level 9 is about a month of ordinary use, level 14 about half a year, and
/// level 20 is years. Past the table it keeps going in even steps, so there is
/// never a last level.
///
/// Steps use the same ladder scaled up, not a ladder of their own, so a level
/// means roughly the same amount of time committed whichever way it was earned:
/// somebody doing a few sets a day moves about thirty reps, and somebody walking
/// moves about seven thousand steps.
enum ExerciseLevel {

    /// Lifetime reps needed to reach levels 1 to 20.
    static let ladder: [Int] = [
        10, 25, 50, 100, 200, 350, 500, 750, 1_000, 1_500,
        2_000, 3_000, 4_000, 5_000, 7_500, 10_000, 15_000, 20_000, 30_000, 50_000,
    ]

    /// Every level past the table costs this much more than the one before.
    static let beyondLadder = 25_000

    /// Steps per rep on the ladder. Level 9 is 200,000 steps, about a month of
    /// walking, the same month level 9 takes in sets.
    static let stepsPerRep = 200

    private static func scale(for exercise: Exercise) -> Int {
        exercise == .steps ? stepsPerRep : 1
    }

    /// Lifetime count needed to reach `level`. Level 0 needs nothing.
    static func threshold(level: Int, for exercise: Exercise) -> Int {
        guard level > 0 else { return 0 }
        let reps = level <= ladder.count
            ? ladder[level - 1]
            : ladder[ladder.count - 1] + (level - ladder.count) * beyondLadder
        return reps * scale(for: exercise)
    }

    struct Progress: Equatable {
        let count: Int
        let level: Int
        /// What this level took, and what the next one takes.
        let floor: Int
        let next: Int

        var remaining: Int { max(0, next - count) }

        /// How far through this level, 0 to 1, for the ring.
        var fraction: Double {
            guard next > floor else { return 1 }
            return min(1, max(0, Double(count - floor) / Double(next - floor)))
        }
    }

    static func progress(count: Int, for exercise: Exercise) -> Progress {
        let count = max(0, count)
        var level = 0
        while count >= threshold(level: level + 1, for: exercise) { level += 1 }
        return Progress(
            count: count,
            level: level,
            floor: threshold(level: level, for: exercise),
            next: threshold(level: level + 1, for: exercise)
        )
    }
}
