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

    /// A colour per level, so every level-up visibly changes the body part it
    /// trained. Warm first, through purple and blue to green, ending in gold,
    /// which every level past the table keeps. Level 0 has none: untrained is
    /// the figure's own grey.
    static let tints: [UInt32] = [
        0xFFE08A, 0xFFC857, 0xFFA94D, 0xFF8A3D, 0xF06027,
        0xE8453C, 0xD62F4B, 0xC2255C, 0xA61E7A, 0x862E9C,
        0x6741D9, 0x4C6EF5, 0x228BE6, 0x15AABF, 0x12B886,
        0x40C057, 0x82C91E, 0xC9B400, 0xF5A300, 0xD4A017,
    ]

    static func tint(level: Int) -> UInt32? {
        guard level > 0 else { return nil }
        return tints[min(level, tints.count) - 1]
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

/// The parts of the figure on Progress that can change colour, and how much
/// each movement works them.
///
/// A region's level comes from every movement that trains it, not one. Walking
/// is mostly calves but it works the thighs too; squats are mostly thighs but
/// work the calves and core; push-ups are chest first, then the front of the
/// shoulders and the triceps, with the core holding the plank. Each movement's
/// volume is converted to reps (steps at `ExerciseLevel.stepsPerRep`), weighted
/// per region, added up, and climbs the same ladder as the rings.
///
/// So the rings and the body answer different questions: a ring is how much of
/// one movement, the body is how much each muscle has been worked by all of
/// them together.
enum BodyRegion: CaseIterable {
    case chest, shoulders, arms, core, thighs, calves

    /// How much one rep of a movement counts toward this region. 1 is the
    /// movement's main job; 0 is not at all.
    func weight(for exercise: Exercise) -> Double {
        switch (exercise, self) {
        case (.pushUps, .chest):     return 1.0
        case (.pushUps, .shoulders): return 0.7
        case (.pushUps, .arms):      return 0.7
        case (.pushUps, .core):      return 0.4
        case (.squats, .thighs):     return 1.0
        case (.squats, .calves):     return 0.4
        case (.squats, .core):       return 0.3
        case (.steps, .calves):      return 1.0
        case (.steps, .thighs):      return 0.5
        default:                     return 0
        }
    }

    /// The region's level from lifetime volumes: reps for push-ups and squats,
    /// steps for walking.
    func level(volumes: [Exercise: Int]) -> Int {
        let reps = volumes.reduce(0.0) { total, entry in
            let (exercise, count) = entry
            let asReps = exercise == .steps
                ? Double(count) / Double(ExerciseLevel.stepsPerRep)
                : Double(count)
            return total + asReps * weight(for: exercise)
        }
        return ExerciseLevel.progress(count: Int(reps), for: .pushUps).level
    }

    var assetName: String {
        switch self {
        case .chest:     return "LevelFigureChest"
        case .shoulders: return "LevelFigureShoulders"
        case .arms:      return "LevelFigureArms"
        case .core:      return "LevelFigureCore"
        case .thighs:    return "LevelFigureThighs"
        case .calves:    return "LevelFigureCalves"
        }
    }
}
