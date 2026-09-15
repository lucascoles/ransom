import DeviceActivity
import SwiftUI

/// Minutes per calendar day across everything the filter returned.
///
/// The app asks for `.daily` segments, so each segment is one day; they are
/// keyed by the start of their day and summed across users and devices, the same
/// way `TotalActivityReport` sums them for today.
private func minutesByDay(_ data: DeviceActivityResults<DeviceActivityData>) async -> [Date: Int] {
    let calendar = Calendar.current
    var seconds: [Date: TimeInterval] = [:]
    for await result in data {
        for await segment in result.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            seconds[day, default: 0] += segment.totalActivityDuration
        }
    }
    return seconds.mapValues { Int($0 / 60) }
}

// MARK: - Today against yesterday

struct DayPair {
    var today: Int
    /// Yesterday from midnight up to this time of day.
    var yesterdaySoFar: Int
    var yesterdayTotal: Int

    var verdict: ScreenTimeSummary.Verdict {
        ScreenTimeSummary.verdict(today: today, yesterdaySoFar: yesterdaySoFar, yesterdayTotal: yesterdayTotal)
    }
}

/// Asked for in hourly segments (see `ScreenTimeComparisonCard`), so yesterday
/// can be cut off at this time of day. The hour that straddles the cut counts
/// in proportion: at 10:20 this morning, yesterday's 10 o'clock hour counts a
/// third.
struct ComparisonReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .comparison
    let content: (DayPair) -> ComparisonView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> DayPair {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let sameTimeYesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? yesterday

        var todaySeconds: TimeInterval = 0
        var soFarSeconds: TimeInterval = 0
        var yesterdaySeconds: TimeInterval = 0
        for await result in data {
            for await segment in result.activitySegments {
                let interval = segment.dateInterval
                let seconds = segment.totalActivityDuration
                if interval.start >= today {
                    todaySeconds += seconds
                } else if interval.start >= yesterday {
                    yesterdaySeconds += seconds
                    if interval.end <= sameTimeYesterday {
                        soFarSeconds += seconds
                    } else if interval.start < sameTimeYesterday, interval.duration > 0 {
                        soFarSeconds += seconds * sameTimeYesterday.timeIntervalSince(interval.start) / interval.duration
                    }
                }
            }
        }
        return DayPair(today: Int(todaySeconds / 60),
                       yesterdaySoFar: Int(soFarSeconds / 60),
                       yesterdayTotal: Int(yesterdaySeconds / 60))
    }
}

/// Both days from the same source as the total above it, so the bar marked
/// "Today" always matches the figure the user has just read.
struct ComparisonView: View {
    let pair: DayPair

    var body: some View {
        Group {
            switch pair.verdict {
            case .change(let change):
                comparison(change)
            case .tooEarly:
                message("Too early to call",
                        "Rex holds today up against this time yesterday. Look in again later and he will tell you which way it is going.")
            case .noYesterday:
                message("No yesterday to compare with",
                        "Screen Time has nothing for yesterday on this phone yet. Look in tomorrow and Rex can tell you which way it went.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ReportFont.headline(16))
                .foregroundStyle(ReportPalette.ink)
            Text(body)
                .font(ReportFont.body(14))
                .foregroundStyle(ReportPalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func comparison(_ change: Int) -> some View {
        let direction = ScreenTimeSummary.direction(change)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ScreenTimeSummary.headline(change))
                    .font(ReportFont.display(34))
                    .foregroundStyle(tint(direction))
                Text("vs this time yesterday")
                    .font(ReportFont.body(15))
                    .foregroundStyle(ReportPalette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            let peak = Double(max(pair.today, pair.yesterdaySoFar, 1))
            VStack(spacing: 8) {
                row("Today", minutes: pair.today, fraction: Double(pair.today) / peak, colour: tint(direction))
                row("Yesterday", minutes: pair.yesterdaySoFar, fraction: Double(pair.yesterdaySoFar) / peak, colour: ReportPalette.hairline)
            }

            HStack(spacing: 8) {
                Image(systemName: icon(direction))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint(direction))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint(direction).opacity(0.14)))
                Text(ScreenTimeSummary.line(change))
                    .font(ReportFont.body(14))
                    .foregroundStyle(ReportPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ label: String, minutes: Int, fraction: Double, colour: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(ReportFont.caption(12))
                .foregroundStyle(ReportPalette.inkSoft)
                .frame(width: 68, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ReportPalette.surfaceAlt)
                    Capsule()
                        .fill(colour)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 10)

            Text(ScreenTimeSummary.clock(minutes))
                .font(ReportFont.caption(12))
                .foregroundStyle(ReportPalette.ink)
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// Green is the app's "earned" colour and belongs to a day going the right
    /// way. Up is tangerine, not red: more screen time than yesterday is a thing
    /// to notice, not a failure to be told off for.
    private func tint(_ direction: ScreenTimeSummary.Direction) -> Color {
        switch direction {
        case .down:  return ReportPalette.green
        case .up:    return ReportPalette.brand
        case .level: return ReportPalette.inkSoft
        }
    }

    private func icon(_ direction: ScreenTimeSummary.Direction) -> String {
        switch direction {
        case .down:  return "arrow.down"
        case .up:    return "arrow.up"
        case .level: return "equal"
        }
    }
}

// MARK: - The week

struct TrendReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .trend
    let content: (ScreenTimeSummary.Week) -> TrendView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTimeSummary.Week {
        let byDay = await minutesByDay(data)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<15).reversed().map { back -> Int in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return 0 }
            return byDay[day] ?? 0
        }
        return ScreenTimeSummary.Week(days: days)
    }
}

/// The week as a line, with the average of the finished days above it.
struct TrendView: View {
    let week: ScreenTimeSummary.Week

    private var weekdays: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return day.formatted(.dateTime.weekday(.narrow))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if week.chart.allSatisfy({ $0 == nil }) {
                Text("Nothing recorded yet. This fills in a day at a time.")
                    .font(ReportFont.body(14))
                    .foregroundStyle(ReportPalette.inkSoft)
                    .padding(.vertical, 18)
            } else {
                TrendLine(points: week.chart)
                    .frame(height: 110)

                HStack(spacing: 0) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(ReportFont.caption(11))
                            .foregroundStyle(ReportPalette.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily screen time")
                    .font(ReportFont.headline(16))
                    .foregroundStyle(ReportPalette.ink)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(week.average.map(ScreenTimeSummary.clock) ?? "-")
                        .font(ReportFont.display(30))
                        .foregroundStyle(ReportPalette.ink)
                    Text("a day")
                        .font(ReportFont.caption(12))
                        .foregroundStyle(ReportPalette.inkSoft)
                }
            }

            Spacer()

            // Down is the good direction here, the opposite of most charts, so
            // it is coloured rather than left for the reader to work out.
            if let change = week.change {
                let better = change <= 0
                Text("\(better ? "↓" : "↑") \(abs(change))%")
                    .font(ReportFont.headline(13))
                    .foregroundStyle(better ? ReportPalette.green : ReportPalette.danger)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(better ? ReportPalette.greenSoft : ReportPalette.brandSoft))
            }
        }
    }
}

/// A line through the week, with a dot on every day that was recorded.
///
/// Days with no reading break the line rather than being drawn as zero. A gap
/// says "not recorded"; a point on the floor says "they used nothing", and those
/// are completely different claims to make about somebody's day.
private struct TrendLine: View {
    var points: [Int?]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let top = max(points.compactMap { $0 }.max() ?? 1, 1)

            let spots: [CGPoint?] = points.enumerated().map { index, value in
                guard let value else { return nil }
                let x = points.count > 1
                    ? width * CGFloat(index) / CGFloat(points.count - 1)
                    : width / 2
                let y = height - (height - 6) * CGFloat(value) / CGFloat(top)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                ForEach(0..<3, id: \.self) { row in
                    let y = height * CGFloat(row) / 2
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: width, y: y)) }
                        .stroke(ReportPalette.hairline, lineWidth: 1)
                }

                Path { path in
                    var pen = false
                    for spot in spots {
                        guard let spot else { pen = false; continue }
                        if pen { path.addLine(to: spot) } else { path.move(to: spot); pen = true }
                    }
                }
                .stroke(ReportPalette.brand, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                    if let spot {
                        Circle()
                            .fill(ReportPalette.brand)
                            .frame(width: 7, height: 7)
                            .position(spot)
                    }
                }
            }
        }
    }
}
