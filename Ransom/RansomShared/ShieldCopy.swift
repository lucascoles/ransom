import Foundation

/// Rex's lines on the block screen. A friend at the door, not a bouncer.
///
/// The shield is a fixed template. Apple gives an icon, a title, a subtitle and
/// two buttons, and no way to lay out anything else, so each slot does one job:
/// the title is the deal in numbers, the subtitle is the one thing to do about
/// it, and the button names that thing. Nothing here explains the rules. The
/// numbers are the rules, and somebody reaching for Instagram reads the numbers
/// and nothing else.
public enum ShieldCopy {

    /// Everything the block screen knows, gathered once so every line is written
    /// from the same facts. Both shield extensions build one of these, which is
    /// what stops the screen and the handoff notification quoting two prices.
    public struct Deal: Equatable {
        /// The app being reached for, when the system tells us. Web domains
        /// arrive as "instagram.com", which reads fine in a sentence.
        public var appName: String?
        /// One set of the plan's movement, in that movement's own unit. Already
        /// scaled for the movement and for any focus rule the app knew about.
        public var reps: Int
        /// The movement's display title as the app mirrored it: "Push-ups".
        public var movement: String
        /// Minutes one set banks.
        public var minutes: Int
        /// Minutes banked and not yet spent.
        public var banked: Int
        /// Steps accumulate on their own from the pedometer. There is no set to
        /// start, so every line that says "do a set" needs another sentence.
        public var isPassive: Bool
        /// The focus rule running right now, if any, and when it lets go.
        public var ruleName: String?
        public var ruleEndMinutes: Int?

        public init(appName: String?, reps: Int, movement: String, minutes: Int,
                    banked: Int, isPassive: Bool,
                    ruleName: String? = nil, ruleEndMinutes: Int? = nil) {
            self.appName = appName
            self.reps = reps
            self.movement = movement
            self.minutes = minutes
            self.banked = banked
            self.isPassive = isPassive
            self.ruleName = ruleName
            self.ruleEndMinutes = ruleEndMinutes
        }

        /// The deal as the App Group currently describes it.
        public init(appName: String?,
                    ledger: UnlockLedger = UnlockLedger(),
                    rules: FocusRuleStore = FocusRuleStore(),
                    now: Date = Date()) {
            let movement = ledger.exerciseName
            let exercise = Exercise.allCases.first { $0.title == movement }
            let rule = rules.activeRule(at: now)
            self.init(
                appName: appName,
                reps: ledger.repsPerUnlock,
                movement: movement,
                minutes: ledger.minutesPerUnlock,
                banked: ledger.bankedMinutes,
                isPassive: exercise?.isPassive ?? false,
                ruleName: rule?.name,
                ruleEndMinutes: rule?.endMinutes
            )
        }

        // MARK: Fragments

        /// "10 push-ups", "1 squat", "1,500 steps".
        var repsPhrase: String {
            var unit = movement.lowercased()
            if reps == 1, unit.hasSuffix("s") { unit.removeLast() }
            return "\(reps.formatted()) \(unit)"
        }

        /// The app by name, or a plain stand-in that still makes the sentence.
        var appLabel: String { appName ?? "this app" }

        /// Deliberately no "spendable" figure any more.
        ///
        /// There used to be one, `min(banked, minutes)`, and the shield quoted it
        /// as "Spend 15 on Instagram". That is not the deal: `spendOptions`
        /// offers one, two and three sets' worth *and* the whole remaining
        /// balance, so somebody with 60 banked can spend all 60. Naming a single
        /// figure on the door promised less than the app gives, and the door is
        /// the last place to undersell yourself.

        /// "Gym Time is on until 6:30 PM." Only the fact. The reps figure says
        /// what that does to the set, so this line does not have to.
        var ruleLine: String? {
            guard let ruleName else { return nil }
            guard let ruleEndMinutes,
                  let end = Calendar.current.date(bySettingHour: ruleEndMinutes / 60,
                                                  minute: ruleEndMinutes % 60,
                                                  second: 0, of: Date())
            else { return "\(ruleName) is on." }
            return "\(ruleName) is on until \(end.formatted(date: .omitted, time: .shortened))."
        }
    }

    // MARK: - The screen

    /// The deal, in numbers. The eye lands on the first digit, so the number the
    /// user has to act on comes first: the set when the bank is empty, the
    /// balance when it is not.
    public static func title(_ deal: Deal) -> String {
        if deal.banked > 0 { return "\(minutes(deal.banked)) in the bank" }
        return "\(deal.repsPhrase) for \(minutes(deal.minutes))"
    }

    /// What to do about it. One or two short sentences; the shield wraps them.
    ///
    /// This used to be the balance alone ("Nothing in the bank."), on the theory
    /// that the balance is the only thing that changes what you do next. It is
    /// not: the set is what decides whether you do anything at all, and a line
    /// that only says what you have not got reads as a shrug.
    public static func subtitle(_ deal: Deal) -> String {
        var lines: [String] = []
        if let rule = deal.ruleLine { lines.append(rule) }

        if deal.banked > 0 {
            // No figure here on purpose: spend as little or as much as you like,
            // up to the whole balance.
            lines.append(deal.isPassive
                ? "Rex takes minutes. Spend what you like, or keep walking for more."
                : "Rex takes minutes. Spend what you like, or do \(deal.repsPhrase) for \(deal.minutes) more.")
        } else {
            // With a rule running, the rule is the news; three sentences is a
            // paragraph, and nobody reads a paragraph on a locked door.
            if deal.ruleName == nil { lines.append("Rex doesn't take cash.") }
            lines.append(deal.isPassive
                ? "Your steps are already paying for it."
                : "One set and he steps aside.")
        }
        return lines.joined(separator: " ")
    }

    /// The way out, named for the one actually available.
    ///
    /// A tap here cannot open Ransom (an extension has no way to launch its host
    /// app), so it closes the shield and posts the handoff notification. The
    /// label still names the outcome rather than the mechanism: "Start my set" is
    /// what the user is deciding to do, and the notification is just the next tap.
    public static func primaryButton(_ deal: Deal) -> String {
        if deal.banked > 0 { return deal.isPassive ? "Spend my minutes" : "Spend or earn" }
        return deal.isPassive ? "See my steps" : "Start my set"
    }

    /// Walking away is allowed and gets no speech.
    public static let secondaryButton = "Not now"

    // MARK: - The handoff notification

    /// Tapping the primary button cannot open Ransom, so the shield hands off
    /// through a notification, and the tap on that is what actually opens the app.
    public static func handoff(_ deal: Deal) -> String {
        if deal.isPassive { return "Tap to open Ransom" }
        return deal.banked > 0 ? "Tap to spend or earn" : "Tap to start your set"
    }

    public static func handoffBody(_ deal: Deal) -> String {
        if deal.isPassive {
            return "Your steps are banking minutes for \(deal.appLabel). See where you're at."
        }
        if deal.banked > 0 {
            return "\(minutes(deal.banked)) banked. Spend what you like on \(deal.appLabel), or do \(deal.repsPhrase) for \(deal.minutes) more."
        }
        return "\(deal.repsPhrase) and you're back in \(deal.appLabel)."
    }

    // MARK: - Helpers

    private static func minutes(_ count: Int) -> String {
        count == 1 ? "1 minute" : "\(count) minutes"
    }
}
