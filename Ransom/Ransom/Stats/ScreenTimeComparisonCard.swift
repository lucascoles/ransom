import SwiftUI

/// Today's screen time against yesterday's, and one line about it.
///
/// The number above this card says how long the phone has been on today, which
/// answers "how am I doing" only if you happen to remember yesterday. This is
/// the comparison, which is the part people actually read.
///
/// **Both days always come from the same series.** Mixing them would produce a
/// number that looks precise and means nothing, which is the exact mistake the
/// baseline made before it was fixed. Which series is used, and why there are
/// two to choose between, is on `pair`.
struct ScreenTimeComparisonCard: View {
    @Environment(AppModel.self) private var model

    /// Both days from one series, and a fallback when the precise one is missing.
    ///
    /// The two series now measure the same thing at different resolutions. Since
    /// the benchmark became whole-phone screen time, `UsageMeter` registers its
    /// events with empty token sets, so `guarded` holds whole-phone minutes in
    /// fifteen-minute rungs, written by the monitor extension every day with no
    /// holes. `device` is the same quantity to the minute, but only exists on
    /// days the report extension rendered, which means days somebody opened this
    /// screen.
    ///
    /// So: prefer `device` when both days have it, fall back to `guarded` when
    /// they do not, and never mix the two. The first version had no fallback and
    /// showed nothing at all until the precise figure existed for two days
    /// running, which for most people is never.
    private var pair: (today: Int, yesterday: Int, coarse: Bool)? {
        _ = model.usageRevision
        guard let day = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        let history = UsageHistory()

        if let now = DeviceUsageStore().minutesToday,
           let then = history.minutes(.device, on: day), then > 0 {
            return (now, then, false)
        }
        if let now = history.minutes(.guarded, on: Date()),
           let then = history.minutes(.guarded, on: day), then > 0 {
            return (now, then, true)
        }
        return nil
    }

    private var hasAnythingToday: Bool {
        _ = model.usageRevision
        return DeviceUsageStore().minutesToday != nil
            || UsageHistory().minutes(.guarded, on: Date()) != nil
    }

    /// Signed percentage change. Negative is less screen time, which is the win.
    private func change(_ p: (today: Int, yesterday: Int, coarse: Bool)) -> Int {
        Int(((Double(p.today - p.yesterday) / Double(p.yesterday)) * 100).rounded())
    }

    var body: some View {
        if let p = pair {
            let change = change(p)
            let today = p.today
            let yesterday = p.yesterday
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline(change))
                        .font(RansomFont.display(34))
                        .foregroundStyle(tint(change))
                    Text("vs yesterday")
                        .font(RansomFont.body(15))
                        .foregroundStyle(Palette.inkSoft)
                }

                bar(today: today, yesterday: yesterday, change: change)

                if p.coarse {
                    Text("Counted in fifteen minute steps until this screen has been open a while.")
                        .font(RansomFont.caption(11))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Image(systemName: icon(change))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint(change))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(tint(change).opacity(0.14)))
                    Text(line(change))
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .ransomCard()
        } else if hasAnythingToday {
            // Measured today, nothing to measure it against.
            VStack(alignment: .leading, spacing: 6) {
                Text("No yesterday to compare with")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Text("Rex only sees your whole phone while this screen is open. Look in tomorrow and he can tell you which way it went.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ransomCard()
        }
    }

    /// Two bars to the same scale, so the comparison is a picture as well as a
    /// percentage. Yesterday is the quiet one; today carries the colour.
    private func bar(today: Int, yesterday: Int, change: Int) -> some View {
        let peak = Double(max(today, yesterday, 1))
        return VStack(spacing: 8) {
            row(label: "Today", minutes: today, fraction: Double(today) / peak, colour: tint(change))
            row(label: "Yesterday", minutes: yesterday, fraction: Double(yesterday) / peak, colour: Palette.hairline)
        }
    }

    private func row(label: String, minutes: Int, fraction: Double, colour: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 68, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceAlt)
                    Capsule()
                        .fill(colour)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 10)

            Text(clock(minutes))
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - What it says

    private func headline(_ change: Int) -> String {
        change > 0 ? "+\(change)%" : "\(change)%"
    }

    /// Green is the app's "earned" colour and it belongs to a day going the right
    /// way. Up is tangerine, not red: more screen time than yesterday is a thing
    /// to notice at four in the afternoon, not a failure to be told off for.
    /// The boundaries match `line` exactly. They did not at first: `>= 5` painted
    /// the arrow and the figure as "up" while the sentence underneath still read
    /// "about level", so a five percent day argued with itself.
    private func tint(_ change: Int) -> Color {
        if change < -5 { return Palette.green }
        if change > 5 { return Palette.brand }
        return Palette.inkSoft
    }

    private func icon(_ change: Int) -> String {
        if change < -5 { return "arrow.down" }
        if change > 5 { return "arrow.up" }
        return "equal"
    }

    /// Motivating in both directions, and honest in both. A good day gets credit.
    /// A worse one gets the day it has left, not a scolding: nobody ever put
    /// their phone down because an app was disappointed in them.
    private func line(_ change: Int) -> String {
        switch change {
        case ..<(-25):  return "Way down on yesterday. Rex is impressed, and he does not say that often."
        case -25 ..< -5: return "Under yesterday. That is the direction."
        case -5...5:    return "About level with yesterday. Hold it there."
        case 6...25:    return "Up a bit on yesterday. Plenty of day left to pull it back."
        default:        return "Well up on yesterday. One set is all it takes to start turning it around."
        }
    }

    private func clock(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
