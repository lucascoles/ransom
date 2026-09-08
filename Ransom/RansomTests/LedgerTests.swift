import Foundation
import Testing
@testable import RansomShared

/// The bank.
///
/// These are the tests worth having first, because every bug here is a bug that
/// silently takes minutes off somebody who paid for them with push-ups, and none
/// of them are visible in the UI until a user writes "the numbers don't add up"
/// in a review.
///
/// Every test runs against its own `UserDefaults` suite so they neither touch the
/// real App Group nor each other.
@Suite("Unlock ledger")
struct LedgerTests {

    /// A ledger nobody else is writing to.
    private func freshLedger(_ name: String = UUID().uuidString) -> (UnlockLedger, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (UnlockLedger(defaults: defaults), defaults)
    }

    // MARK: - Banking

    @Test("Banking adds to the balance")
    func bankingAccumulates() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 10)
        ledger.bank(minutes: 5)
        #expect(ledger.bankedMinutes == 15)
    }

    @Test("Banking zero or negative minutes is ignored")
    func bankingRejectsNonPositive() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 10)
        ledger.bank(minutes: 0)
        ledger.bank(minutes: -30)
        #expect(ledger.bankedMinutes == 10)
    }

    // MARK: - Spending

    @Test("Spending debits the bank and records the spend")
    func spendingDebits() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 30)
        let spent = ledger.spend(minutes: 10)
        #expect(spent == 10)
        #expect(ledger.bankedMinutes == 20)
        #expect(ledger.spentMinutesToday == 10)
    }

    /// The balance is a floor as well as a ceiling. Overdrawing it would hand out
    /// minutes nobody earned.
    @Test("Spending more than the balance takes only what is there")
    func spendingCannotOverdraw() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 5)
        let spent = ledger.spend(minutes: 25)
        #expect(spent == 5)
        #expect(ledger.bankedMinutes == 0)
        #expect(ledger.spentMinutesToday == 5)
    }

    @Test("Spending from an empty bank is a no-op")
    func spendingEmptyBank() {
        let (ledger, _) = freshLedger()
        let spent = ledger.spend(minutes: 15)
        #expect(spent == 0)
        #expect(ledger.spentMinutesToday == 0)
    }

    /// `spend` deliberately does not open the apps. It did once, at the same time
    /// as `grantEarnedTime`, and a fifteen-minute purchase unlocked for thirty.
    @Test("Spending does not start the clock")
    func spendingDoesNotUnlock() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 20)
        _ = ledger.spend(minutes: 10)
        #expect(ledger.isUnlocked == false)
        #expect(ledger.expiry == nil)
    }

    // MARK: - The daily rollover

    /// Use it or lose it. A balance that carries over lets a keen first week fund
    /// a month of scrolling, which is the habit this app exists to break.
    @Test("A balance from yesterday is gone this morning")
    func bankExpiresOvernight() {
        let (ledger, defaults) = freshLedger()
        ledger.bank(minutes: 45)
        #expect(ledger.bankedMinutes == 45)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        defaults.set(yesterday, forKey: RansomCore.Key.bankDay)

        #expect(ledger.bankedMinutes == 0)
    }

    @Test("Minutes spent yesterday do not count against today")
    func spendResetsOvernight() {
        let (ledger, defaults) = freshLedger()
        ledger.bank(minutes: 30)
        _ = ledger.spend(minutes: 30)
        #expect(ledger.spentMinutesToday == 30)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        defaults.set(yesterday, forKey: RansomCore.Key.spentDay)

        #expect(ledger.spentMinutesToday == 0)
    }

    /// Banking after a rollover starts from zero rather than resurrecting the old
    /// balance, which is what a naive `+=` against a stale day would do.
    @Test("Banking after a rollover starts clean")
    func bankingAfterRollover() {
        let (ledger, defaults) = freshLedger()
        ledger.bank(minutes: 60)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        defaults.set(yesterday, forKey: RansomCore.Key.bankDay)

        ledger.bank(minutes: 10)
        #expect(ledger.bankedMinutes == 10)
    }

    // MARK: - Unlock windows

    @Test("Granting minutes opens the door for exactly that long")
    func grantSetsExpiry() {
        let (ledger, _) = freshLedger()
        let now = Date()
        let expiry = ledger.grant(minutes: 15, now: now)
        #expect(abs(expiry.timeIntervalSince(now) - 15 * 60) < 1)
        #expect(ledger.isUnlocked)
    }

    /// Buying again mid-unlock has to extend, not restart. Restarting silently
    /// throws away whatever was left on the clock.
    @Test("A second grant extends the time left rather than replacing it")
    func grantExtends() {
        let (ledger, _) = freshLedger()
        let now = Date()
        _ = ledger.grant(minutes: 10, now: now)
        let expiry = ledger.grant(minutes: 10, now: now.addingTimeInterval(60))
        // Five minutes of the first grant were still unspent, so twenty minutes
        // were bought and one was used: nineteen remain.
        #expect(abs(expiry.timeIntervalSince(now) - 20 * 60) < 1)
    }

    /// An expired unlock is not a running one, so a fresh grant measures from now
    /// and does not add to a window that already closed.
    @Test("Granting after expiry starts from now")
    func grantAfterExpiry() {
        let (ledger, _) = freshLedger()
        let past = Date().addingTimeInterval(-3600)
        _ = ledger.grant(minutes: 5, now: past)
        #expect(ledger.isUnlocked == false)

        let now = Date()
        let expiry = ledger.grant(minutes: 10, now: now)
        #expect(abs(expiry.timeIntervalSince(now) - 10 * 60) < 1)
    }

    @Test("Revoking closes the door but keeps the bank")
    func revokeKeepsBank() {
        let (ledger, _) = freshLedger()
        ledger.bank(minutes: 25)
        _ = ledger.grant(minutes: 10)
        ledger.revoke()
        #expect(ledger.isUnlocked == false)
        #expect(ledger.bankedMinutes == 25)
    }
}
