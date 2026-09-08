import SwiftUI

/// Today's screen time against yesterday's, and one line about it.
///
/// The number above this card says how long the phone has been on today, which
/// answers "how am I doing" only if you happen to remember yesterday. This is
/// the comparison, which is the part people actually read.
///
/// **Both figures come from the same series on purpose.** `UsageHistory` keeps
/// two: `guarded`, which the monitor extension writes every day whether or not
/// anybody opens the app, and `device`, the whole phone, which only exists on
/// days the report extension rendered - that is, days the user opened Progress.
/// The card above shows the device figure, so this compares device against
/// device. Comparing today's whole phone against yesterday's guarded apps would
/// produce a number that looks precise and means nothing, which is the exact
/// mistake the baseline had before it was fixed.
///
/// So when yesterday is missing, this says so and offers nothing else. A first
/// day with no comparison is honest. An invented one is not.
struct ScreenTimeComparisonCard: View {
    @Environment(AppModel.self) private var model

    private var today: Int? {
        _ = model.usageRevision
        return DeviceUsageStore().minutesToday
    }

    private var yesterday: Int? {
        _ = model.usageRevision
        guard let day = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        return UsageHistory().minutes(.device, on: day)
    }

    /// Signed percentage change. Negative is less screen time, which is the win.
    private var change: Int? {
        guard let today, let yesterday, yesterday > 0 else { return nil }
        return Int(((Double(today - yesterday) / Double(yesterday)) * 100).rounded())
    }

    var body: some View {
        if let change, let today, let yesterday {
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
        } else if today != nil {
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
    private func tint(_ change: Int) -> Color {
        if change <= -5 { return Palette.green }
        if change >= 5 { return Palette.brand }
        return Palette.inkSoft
    }

    private func icon(_ change: Int) -> String {
        if change <= -5 { return "arrow.down" }
        if change >= 5 { return "arrow.up" }
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
