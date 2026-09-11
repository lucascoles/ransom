import SwiftUI

/// The last seven days of walking, with today at the right-hand end.
///
/// A step count on its own is a number without a verdict: 570 is either a slow
/// morning or a dead day, and nothing on the screen said which. The week is what
/// turns it into a judgement the user can actually make, and it is free - the
/// phone has been counting all along and hands back seven days on request.
///
/// Bars rather than the line used on Progress. Screen time is a level that drifts
/// and a line reads it well; a day's steps are a quantity that starts at nothing
/// every midnight, and bars say that where a line implies the days flow into each
/// other.
struct StepWeekCard: View {
    var week: [StepTracker.DayCount]
    /// Where earning stops, drawn as the day's mark to walk past.
    var goal: Int

    private var counts: [Int] { week.compactMap(\.steps) }

    /// The user's own usual, which is the only fair thing to measure a day
    /// against. Today is left out of it: comparing a morning against an average
    /// that contains that same morning drags the bar down toward itself and
    /// makes every day before lunch look average.
    private var typical: Int? {
        let past = week.dropLast().compactMap(\.steps)
        guard !past.isEmpty else { return nil }
        return past.reduce(0, +) / past.count
    }

    private var today: Int? { week.last?.steps }

    /// Only claimed once there is a week to claim it against, and never on a
    /// morning - by nine o'clock every day is "down on your usual", which is
    /// true, useless, and discouraging.
    private var verdict: (text: String, isGood: Bool)? {
        guard let today, let typical, typical > 0 else { return nil }
        guard Calendar.current.component(.hour, from: Date()) >= 12 else { return nil }
        let change = Int(((Double(today) - Double(typical)) / Double(typical) * 100).rounded())
        guard abs(change) >= 5 else { return ("about your usual", true) }
        return change > 0 ? ("↑ \(change)% on your usual", true)
                          : ("↓ \(abs(change))% on your usual", false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if counts.isEmpty {
                Text("Nothing recorded yet. Your phone keeps a week of this and it fills in on its own.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
            } else {
                StepBars(week: week, goal: goal)
                    .frame(height: 108)

                HStack(spacing: 0) {
                    ForEach(week) { day in
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(RansomFont.caption(11))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date)
                                             ? Palette.ink : Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .ransomCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your week")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                if let typical {
                    Text("\(typical.formatted()) steps on a usual day")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
            }

            Spacer()

            // Up is the good direction here, unlike every other chart in the app,
            // so it gets the green rather than the reader having to work it out.
            if let verdict {
                Text(verdict.text)
                    .font(RansomFont.headline(12))
                    .foregroundStyle(verdict.isGood ? Palette.green : Palette.inkSoft)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(verdict.isGood ? Palette.greenSoft : Palette.surfaceAlt)
                    )
            }
        }
    }
}

/// Seven bars and a goal line.
private struct StepBars: View {
    var week: [StepTracker.DayCount]
    var goal: Int

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let best = week.compactMap(\.steps).max() ?? 0
            // The goal stays inside the frame even on a quiet week, so the line
            // never floats off the top and leaves the bars looking like the whole
            // story. On a big day the bars set the scale instead.
            let top = max(best, goal, 1)
            let slot = width / CGFloat(max(week.count, 1))
            let barWidth = min(26, slot * 0.54)
            let goalY = height - height * CGFloat(goal) / CGFloat(top)

            ZStack(alignment: .topLeading) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                    let x = slot * (CGFloat(index) + 0.5)
                    if let steps = day.steps {
                        let isToday = Calendar.current.isDateInToday(day.date)
                        let barHeight = max(3, height * CGFloat(steps) / CGFloat(top))
                        Capsule()
                            .fill(isToday ? Palette.brand : Palette.brandSoft)
                            .frame(width: barWidth, height: barHeight)
                            .position(x: x, y: height - barHeight / 2)
                    } else {
                        // A day the phone cannot account for. Drawn as an outline
                        // so the week keeps its shape without claiming nobody moved.
                        Capsule()
                            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: barWidth, height: 3)
                            .position(x: x, y: height - 1.5)
                    }
                }

                Path {
                    $0.move(to: CGPoint(x: 0, y: goalY))
                    $0.addLine(to: CGPoint(x: width, y: goalY))
                }
                .stroke(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }
}
