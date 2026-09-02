import Foundation

/// Progressive pricing for unlocks.
///
/// Flat friction is the mistake every app in this category makes: it taxes the
/// person who opens Instagram twice a day exactly as hard as the person who opens
/// it fifteen times, and after a fortnight both have stopped noticing it.
///
/// The tariff taxes the *binge* instead. The first couple of unlocks each day cost
/// the base price. After that the price climbs, so a normal day is barely touched
/// and a doomscrolling spiral gets progressively more expensive to continue.
///
/// Three rules keep it fair rather than punitive:
///  1. **It's capped.** The price never exceeds 3x base, so the door is never shut.
///  2. **It's predictable.** The whole ladder is visible in the app and the shield
///     quotes the price before you commit to the set.
///  3. **Spacing earns a discount.** Leave the apps alone for a few hours and you
///     drop a tier. Ransom is trying to break the spiral, not punish the day.
public struct Tariff: Sendable {

    // MARK: - Configuration

    /// Multiplier applied once the day's unlock count reaches each threshold.
    /// Read as: "from your Nth unlock onward, pay this much."
    public static let ladder: [(fromUnlock: Int, multiplier: Double)] = [
        (1, 1.0),
        (3, 1.5),
        (4, 2.0),
        (5, 2.5),
        (6, 3.0)
    ]

    /// Nothing ever costs more than this, however bad the day gets.
    public static let cap: Double = 3.0

    /// A hard ceiling on a single set, whatever the multiplier says.
    ///
    /// The multiplier cap alone isn't enough: a Beast-mode user with a base of 28
    /// would be quoted 84 push-ups for one unlock, which nobody does — they'd just
    /// uninstall. This is a placeholder worth tuning per movement once there's
    /// real usage data; 40 is achievable-but-miserable for push-ups and trivial
    /// for jacks, which is roughly the right shape.
    public static let maxRepsPerSet: Int = 40

    /// Surcharge inside the user's declared late-night window. Bedtime scrolling is
    /// the habit people most want broken, and they told us so during intake.
    public static let nightSurcharge: Double = 1.5

    /// Leaving the guarded apps alone this long drops you back a tier.
    public static let coolDown: TimeInterval = 3 * 60 * 60

    /// The window the night surcharge applies to, in local hours.
    public static let nightWindow = (start: 22, end: 5)

    // MARK: - Quoting

    /// What the next unlock costs, and why.
    public struct Quote: Equatable, Sendable {
        /// Reps required for this unlock.
        public let reps: Int
        /// Base reps before any surcharge.
        public let baseReps: Int
        public let multiplier: Double
        /// Which unlock of the day this would be (1-based).
        public let unlockNumber: Int
        public let isLateNight: Bool
        public let earnedCoolDown: Bool

        public var isSurcharged: Bool { multiplier > 1.0 }
        public var isAtCap: Bool { multiplier >= Tariff.cap }

        /// One short line explaining the price, or nil when it's just the base rate.
        public var explanation: String? {
            if earnedCoolDown && isSurcharged {
                return "\(ordinal(unlockNumber)) today — the break earned you a tier back."
            }
            guard isSurcharged else { return nil }
            if isLateNight && unlockNumber >= 3 {
                return "\(ordinal(unlockNumber)) today, and it's late."
            }
            if isLateNight {
                return "Late-night rate."
            }
            return "\(ordinal(unlockNumber)) today. Price went up."
        }

        private func ordinal(_ value: Int) -> String {
            switch value {
            case 1: return "1st"
            case 2: return "2nd"
            case 3: return "3rd"
            default: return "\(value)th"
            }
        }
    }

    // MARK: - Pricing

    /// Prices the next unlock.
    ///
    /// - Parameters:
    ///   - base: the plan's base reps per unlock.
    ///   - unlocksToday: how many unlocks have already been bought today.
    ///   - lastUnlockAt: when the last one was bought, for the cool-down discount.
    ///   - nightSurchargeEnabled: whether the user opted into the late-night rate.
    ///   - now: injectable for tests.
    public static func quote(
        base: Int,
        unlocksToday: Int,
        lastUnlockAt: Date? = nil,
        nightSurchargeEnabled: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Quote {
        // Spacing them out walks you back down the ladder.
        let cooled = lastUnlockAt.map { now.timeIntervalSince($0) >= coolDown } ?? false
        let effectiveCount = max(0, unlocksToday - (cooled ? 1 : 0))
        let unlockNumber = effectiveCount + 1

        let tierMultiplier = ladder
            .last { unlockNumber >= $0.fromUnlock }?
            .multiplier ?? 1.0

        let night = nightSurchargeEnabled && isLateNight(now, calendar: calendar)
        let raw = tierMultiplier * (night ? nightSurcharge : 1.0)
        let capped = min(cap, raw)

        let quotedReps = min(maxRepsPerSet, max(1, Int((Double(base) * capped).rounded())))
        // Report the multiplier actually charged, so the UI can't claim a 3x price
        // it didn't apply once the ceiling bites.
        let multiplier = base > 0 ? Double(quotedReps) / Double(base) : capped

        return Quote(
            reps: quotedReps,
            baseReps: base,
            multiplier: multiplier,
            unlockNumber: unlocksToday + 1,
            isLateNight: night,
            earnedCoolDown: cooled
        )
    }

    public static func isLateNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        // The window wraps midnight, so it's two ranges, not one.
        return hour >= nightWindow.start || hour < nightWindow.end
    }

    /// The whole ladder priced out, for the "today's rates" card. Always shows the
    /// user what's coming — an unpredictable price reads as punishment.
    public static func schedule(base: Int) -> [(unlock: Int, reps: Int, multiplier: Double)] {
        ladder.map { tier in
            let reps = min(maxRepsPerSet, max(1, Int((Double(base) * tier.multiplier).rounded())))
            return (unlock: tier.fromUnlock, reps: reps, multiplier: tier.multiplier)
        }
    }
}
