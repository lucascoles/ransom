import Foundation
import Testing
@testable import RansomShared

/// The price of an unlock.
///
/// `Tariff.quote` is where the app decides how many push-ups scrolling costs
/// right now. It is pure arithmetic over injectable inputs, which makes it the
/// cheapest thing in the codebase to test and one of the most expensive to get
/// wrong: an over-charge is a user who feels cheated, an under-charge is a
/// product that does not work.
@Suite("Tariff")
struct TariffTests {

    /// Mid-afternoon, comfortably outside the night window, in a fixed timezone so
    /// the suite does not change behaviour depending on where it runs.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func time(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 15
        components.hour = hour; components.minute = 0
        return calendar.date(from: components)!
    }

    // MARK: - The ladder

    @Test("The first unlock of the day is charged at the base rate")
    func firstUnlockIsBaseRate() {
        let quote = Tariff.quote(base: 10, unlocksToday: 0,
                                 now: time(hour: 14), calendar: calendar)
        #expect(quote.reps == 10)
        #expect(quote.multiplier == 1.0)
        #expect(quote.isSurcharged == false)
    }

    /// Coming back repeatedly is what the ladder is for.
    @Test("Repeated unlocks get more expensive")
    func priceRisesWithUse() {
        let first = Tariff.quote(base: 10, unlocksToday: 0,
                                 now: time(hour: 14), calendar: calendar)
        let fifth = Tariff.quote(base: 10, unlocksToday: 4,
                                 now: time(hour: 14), calendar: calendar)
        #expect(fifth.reps > first.reps)
    }

    @Test("The multiplier never exceeds the cap")
    func multiplierIsCapped() {
        let quote = Tariff.quote(base: 10, unlocksToday: 50,
                                 now: time(hour: 14), calendar: calendar)
        #expect(quote.multiplier <= Tariff.cap)
    }

    /// A ceiling that a big base rate can punch through is not a ceiling. Forty
    /// push-ups is already past what most people can do in one set.
    @Test("Reps never exceed the per-set maximum")
    func repsAreCapped() {
        let quote = Tariff.quote(base: 30, unlocksToday: 20,
                                 now: time(hour: 14), calendar: calendar)
        #expect(quote.reps <= Tariff.maxRepsPerSet)
    }

    /// The quoted multiplier has to describe the price actually charged. When the
    /// rep ceiling bites, a raw 3x would be a claim the app did not act on.
    @Test("The reported multiplier matches the reps actually charged")
    func multiplierMatchesChargedReps() {
        let quote = Tariff.quote(base: 30, unlocksToday: 20,
                                 now: time(hour: 14), calendar: calendar)
        #expect(abs(quote.multiplier - Double(quote.reps) / 30.0) < 0.001)
    }

    @Test("A quote is never free")
    func quoteIsAlwaysAtLeastOneRep() {
        let quote = Tariff.quote(base: 1, unlocksToday: 0,
                                 now: time(hour: 14), calendar: calendar)
        #expect(quote.reps >= 1)
    }

    // MARK: - The night surcharge

    @Test("Late night costs more when the user opted in")
    func nightSurchargeApplies() {
        let day = Tariff.quote(base: 10, unlocksToday: 0,
                               now: time(hour: 14), calendar: calendar)
        let night = Tariff.quote(base: 10, unlocksToday: 0,
                                 now: time(hour: 23), calendar: calendar)
        #expect(night.isLateNight)
        #expect(night.reps > day.reps)
    }

    /// This is the only switch for the surcharge, and onboarding asks for it as a
    /// real question. Answering "no" has to mean no.
    @Test("Opting out of the night rate means no surcharge")
    func nightSurchargeRespectsOptOut() {
        let quote = Tariff.quote(base: 10, unlocksToday: 0,
                                 nightSurchargeEnabled: false,
                                 now: time(hour: 23), calendar: calendar)
        #expect(quote.isLateNight == false)
        #expect(quote.reps == 10)
    }

    /// The window wraps midnight, which is the classic place for an off-by-one to
    /// hide: 2am is late night, 6am is not.
    @Test("The night window wraps midnight correctly")
    func nightWindowWrapsMidnight() {
        #expect(Tariff.isLateNight(time(hour: 23), calendar: calendar))
        #expect(Tariff.isLateNight(time(hour: 2), calendar: calendar))
        #expect(Tariff.isLateNight(time(hour: 4), calendar: calendar))
        #expect(Tariff.isLateNight(time(hour: 6), calendar: calendar) == false)
        #expect(Tariff.isLateNight(time(hour: 14), calendar: calendar) == false)
    }

    @Test("The window boundaries fall on the right side")
    func nightWindowBoundaries() {
        #expect(Tariff.isLateNight(time(hour: Tariff.nightWindow.start), calendar: calendar))
        #expect(Tariff.isLateNight(time(hour: Tariff.nightWindow.start - 1), calendar: calendar) == false)
        #expect(Tariff.isLateNight(time(hour: Tariff.nightWindow.end), calendar: calendar) == false)
        #expect(Tariff.isLateNight(time(hour: Tariff.nightWindow.end - 1), calendar: calendar))
    }

    // MARK: - The cool-down

    /// Waiting walks you back down the ladder. Without this the price only ever
    /// ratchets, and a single busy morning poisons the rest of the day.
    @Test("Waiting out the cool-down lowers the price")
    func coolDownDiscountsTheNextUnlock() {
        let now = time(hour: 14)
        let recent = Tariff.quote(base: 10, unlocksToday: 3,
                                  lastUnlockAt: now.addingTimeInterval(-60),
                                  now: now, calendar: calendar)
        let rested = Tariff.quote(base: 10, unlocksToday: 3,
                                  lastUnlockAt: now.addingTimeInterval(-Tariff.coolDown - 60),
                                  now: now, calendar: calendar)
        #expect(rested.earnedCoolDown)
        #expect(recent.earnedCoolDown == false)
        #expect(rested.reps <= recent.reps)
    }

    /// The counter shown to the user is how many unlocks they have bought, not the
    /// discounted rung used for pricing. Those diverge after a cool-down and the
    /// UI must not report the internal one.
    @Test("The displayed unlock number ignores the cool-down discount")
    func unlockNumberIsNotDiscounted() {
        let now = time(hour: 14)
        let quote = Tariff.quote(base: 10, unlocksToday: 3,
                                 lastUnlockAt: now.addingTimeInterval(-Tariff.coolDown - 60),
                                 now: now, calendar: calendar)
        #expect(quote.unlockNumber == 4)
    }

    // MARK: - The schedule shown during onboarding

    /// Onboarding prints this table as a promise. If it disagrees with `quote`,
    /// the app quotes one price and charges another.
    @Test("The advertised schedule matches what the tariff actually charges")
    func scheduleMatchesQuotes() {
        let base = 10
        for row in Tariff.schedule(base: base) {
            let quote = Tariff.quote(base: base,
                                     unlocksToday: row.unlock - 1,
                                     nightSurchargeEnabled: false,
                                     now: time(hour: 14), calendar: calendar)
            #expect(quote.reps == row.reps,
                    "unlock \(row.unlock): schedule says \(row.reps), tariff charges \(quote.reps)")
        }
    }
}
