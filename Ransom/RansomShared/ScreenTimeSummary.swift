import Foundation

/// The arithmetic and the words behind the Progress tab's two screen time cards.
///
/// The cards are drawn by the report extension, because that is the only process
/// that ever sees exact screen time: iOS silently drops anything it writes to the
/// App Group, so the figure cannot be handed to the app. Kept here, apart from the
/// drawing, so the tests can reach it.
public enum ScreenTimeSummary {

    // MARK: - Today against yesterday

    /// Signed percentage change. Negative is less screen time, which is the win.
    /// Nil with nothing recorded yesterday: a change against nothing is not one.
    public static func change(today: Int, yesterday: Int) -> Int? {
        guard yesterday > 0 else { return nil }
        return Int(((Double(today - yesterday) / Double(yesterday)) * 100).rounded())
    }

    public enum Direction { case down, level, up }

    /// Five percent either way is level. The figure, the arrow and the sentence
    /// all read from this, so they cannot disagree about a five percent day.
    public static func direction(_ change: Int) -> Direction {
        if change < -5 { return .down }
        if change > 5 { return .up }
        return .level
    }

    public static func headline(_ change: Int) -> String {
        change > 0 ? "+\(change)%" : "\(change)%"
    }

    /// Motivating in both directions, and honest in both. A good day gets credit.
    /// A worse one gets the day it has left, not a scolding: nobody ever put
    /// their phone down because an app was disappointed in them.
    public static func line(_ change: Int) -> String {
        switch change {
        case ..<(-25):   return "Way down on yesterday. Rex is impressed, and he does not say that often."
        case -25 ..< -5: return "Under yesterday. That is the direction."
        case -5...5:     return "About level with yesterday. Hold it there."
        case 6...25:     return "Up a bit on yesterday. Plenty of day left to pull it back."
        default:         return "Well up on yesterday. One set is all it takes to start turning it around."
        }
    }

    // MARK: - The week

    /// Fifteen days of screen time, oldest first, today last.
    ///
    /// Zero is read as "nothing recorded" rather than "a day without the phone":
    /// Screen Time reports zero for days before it was switched on, and a dot on
    /// the floor for those would claim a perfect day nobody had.
    public struct Week: Equatable {
        public let days: [Int]

        public init(days: [Int]) {
            self.days = days
        }

        /// The last seven days, today included, for the line. Nil breaks the line.
        public var chart: [Int?] {
            days.suffix(7).map { $0 > 0 ? $0 : nil }
        }

        /// The seven finished days before today, and the seven before those.
        /// Today is left out of both: at nine in the morning it is a fraction of
        /// a day, and averaging it in made every morning look like a good week.
        private var thisWeek: [Int] { days.dropLast().suffix(7).filter { $0 > 0 } }
        private var lastWeek: [Int] { days.dropLast().dropLast(7).suffix(7).filter { $0 > 0 } }

        public var average: Int? {
            guard !thisWeek.isEmpty else { return nil }
            return thisWeek.reduce(0, +) / thisWeek.count
        }

        /// Only claimed when both weeks have something in them.
        public var change: Int? {
            guard let average, !lastWeek.isEmpty else { return nil }
            let previous = lastWeek.reduce(0, +) / lastWeek.count
            guard previous > 0 else { return nil }
            return Int(((Double(average) - Double(previous)) / Double(previous) * 100).rounded())
        }
    }

    // MARK: - Formatting

    public static func clock(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
