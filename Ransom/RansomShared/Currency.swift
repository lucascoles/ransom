import Foundation

/// What Ransom calls the thing you earn.
///
/// A coin is a minute. Not a second currency with a rate against minutes: the
/// app already asks people to hold one exchange rate in their head (reps buy
/// time), and a second one would be the thing they got wrong. Fifteen coins
/// unlock fifteen minutes, and five coins unlock five.
///
/// The rename is about which of the two words is on screen, and the split is
/// between money and time:
///
/// - **Coins** wherever it is a balance being earned, banked or spent. That is
///   the game, and a number you are collecting wants to look like treasure
///   rather than an allowance.
/// - **Minutes and hours** wherever it is real elapsed time: the countdown on a
///   running unlock, screen-time figures, hours saved, a projection. Those are
///   measurements of the user's life, and dressing them up as points would be
///   the app lying about the one thing it exists to be honest about.
///
/// Every string is built here so the two never drift into each other.
public enum Currency {
    /// "15 coins", "1 coin".
    public static func coins(_ count: Int) -> String {
        count == 1 ? "1 coin" : "\(count.formatted()) coins"
    }

    /// "15" with the word left to a label beside it, for tiles and big numbers.
    public static func amount(_ count: Int) -> String {
        count.formatted()
    }

    /// The word alone, agreeing with the number it is placed near.
    public static func unit(_ count: Int) -> String {
        count == 1 ? "coin" : "coins"
    }

    /// The asset name of the gold coin, so no call site has to remember it.
    public static let symbolName = "coin"
}
