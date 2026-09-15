import Foundation
import Testing
@testable import Ransom

/// Levels per movement, from lifetime volume.
@Suite("Exercise levels")
struct ExerciseLevelTests {

    @Test("Nothing done is level 0, heading for level 1 at one set")
    func startsAtZero() {
        let p = ExerciseLevel.progress(count: 0, for: .pushUps)
        #expect(p.level == 0)
        #expect(p.next == 10)
        #expect(p.remaining == 10)
        #expect(p.fraction == 0)
    }

    @Test("A threshold reached is that level, not the one below")
    func thresholdsAreInclusive() {
        #expect(ExerciseLevel.progress(count: 9, for: .pushUps).level == 0)
        #expect(ExerciseLevel.progress(count: 10, for: .pushUps).level == 1)
        #expect(ExerciseLevel.progress(count: 1_000, for: .squats).level == 9)
        #expect(ExerciseLevel.progress(count: 50_000, for: .pushUps).level == 20)
    }

    @Test("The ring shows progress through the current level only")
    func fractionWithinLevel() {
        // Level 4 is 100, level 5 is 200: 150 is halfway.
        let p = ExerciseLevel.progress(count: 150, for: .pushUps)
        #expect(p.level == 4)
        #expect(p.fraction == 0.5)
        #expect(p.remaining == 50)
    }

    @Test("Past the table the levels keep coming in even steps")
    func beyondTheLadder() {
        #expect(ExerciseLevel.threshold(level: 21, for: .pushUps) == 75_000)
        #expect(ExerciseLevel.threshold(level: 22, for: .pushUps) == 100_000)
        #expect(ExerciseLevel.progress(count: 80_000, for: .pushUps).level == 21)
    }

    @Test("Steps climb the same ladder at 200 steps a rep")
    func stepsScale() {
        #expect(ExerciseLevel.threshold(level: 1, for: .steps) == 2_000)
        #expect(ExerciseLevel.threshold(level: 9, for: .steps) == 200_000)
        #expect(ExerciseLevel.progress(count: 45_000, for: .steps).level == 5)
    }

    @Test("Every level costs more than the one before")
    func ladderRises() {
        for level in 1..<30 {
            #expect(ExerciseLevel.threshold(level: level + 1, for: .pushUps)
                    > ExerciseLevel.threshold(level: level, for: .pushUps))
        }
    }

    @Test("Every level-up changes the colour, and level 0 has none")
    func tintsChangeEachLevel() {
        #expect(ExerciseLevel.tint(level: 0) == nil)
        for level in 1..<ExerciseLevel.tints.count {
            #expect(ExerciseLevel.tint(level: level) != ExerciseLevel.tint(level: level + 1))
        }
        // Past the table, gold stays.
        #expect(ExerciseLevel.tint(level: 40) == ExerciseLevel.tints.last)
    }

    @Test("Each movement colours the muscles it works")
    func regionsFollowTheirMovement() {
        #expect(BodyRegion.chest.trainedBy(walking: true) == .pushUps)
        #expect(BodyRegion.core.trainedBy(walking: false) == .pushUps)
        #expect(BodyRegion.thighs.trainedBy(walking: true) == .squats)
        #expect(BodyRegion.calves.trainedBy(walking: true) == .steps)
        // Nobody walking for minutes: squats work the calves too.
        #expect(BodyRegion.calves.trainedBy(walking: false) == .squats)
    }

    @Test("The step log keeps each day's highest reading and adds the days")
    func stepLog() {
        let defaults = UserDefaults(suiteName: "StepLogTests-\(UUID())")!
        let log = StepLog(defaults: defaults)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        log.record(3_000, on: today)
        log.record(5_200, on: today)
        log.record(4_000, on: today)   // an earlier reading arriving late
        log.record(8_000, on: yesterday)
        #expect(log.lifetime == 13_200)
    }
}
