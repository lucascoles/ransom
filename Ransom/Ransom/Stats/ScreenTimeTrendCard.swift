import SwiftUI

/// Screen time, day by day, with this week measured against last.
///
/// The card this replaced compared today against the average the user typed in
/// during intake - a number they estimated once, months ago, that never moves.
/// It could only ever say the same thing twice. A trend compares them against
/// themselves, which is the only comparison that can show the habit changing.
struct ScreenTimeTrendCard: View {
    @Environment(AppModel.self) private var model

    /// Guarded apps rather than the whole phone. The monitor extension records
    /// that one in the background every day, while the whole-phone figure only
    /// exists on days the user opened this screen - and a line drawn through
    /// missing days is a picture of when somebody used the app, not of their
    /// screen time.
    private var days: [(date: Date, minutes: Int?)] {
        _ = model.usageRevision
        return UsageHistory().recent(.guarded, days: 14)
    }

    private var thisWeek: [Int] { days.suffix(7).compactMap(\.minutes) }
    private var lastWeek: [Int] { days.prefix(7).compactMap(\.minutes) }

    private var average: Int? {
        guard !thisWeek.isEmpty else { return nil }
        return thisWeek.reduce(0, +) / thisWeek.count
    }

    /// Only claimed when both weeks have something in them. A change against a
    /// week that was never measured is not a change.
    private var change: Int? {
        guard let average, !lastWeek.isEmpty else { return nil }
        let previous = lastWeek.reduce(0, +) / lastWeek.count
        guard previous > 0 else { return nil }
        return Int(((Double(average) - Double(previous)) / Double(previous) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if thisWeek.isEmpty {
                Text("Nothing measured yet. This fills in a day at a time.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                TrendLine(points: days.suffix(7).map(\.minutes))
                    .frame(height: 110)

                HStack(spacing: 0) {
                    ForEach(Array(days.suffix(7).enumerated()), id: \.offset) { _, day in
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(RansomFont.caption(11))
                            .foregroundStyle(Palette.inkFaint)
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
                Text("Time in your apps")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(average.map(clock) ?? "-")
                        .font(RansomFont.display(30))
                        .foregroundStyle(Palette.ink)
                    Text("a day")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
            }

            Spacer()

            // Down is the good direction here, which is the opposite of most
            // charts and worth colouring rather than leaving the reader to work
            // out.
            if let change {
                let better = change <= 0
                Text("\(better ? "↓" : "↑") \(abs(change))%")
                    .font(RansomFont.headline(13))
                    .foregroundStyle(better ? Palette.green : Palette.danger)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(better ? Palette.greenSoft : Palette.brandSoft)
                    )
            }
        }
    }

    private func clock(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

/// A line through the week, with a dot on every day that was measured.
///
/// Days with no reading break the line rather than being drawn as zero. A gap
/// says "not measured"; a point on the floor says "they used nothing", and those
/// are completely different claims to make about somebody's day.
private struct TrendLine: View {
    var points: [Int?]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let values = points.compactMap { $0 }
            let top = max(values.max() ?? 1, 1)

            // Placed on the same grid whether or not the day has a value, so a
            // gap leaves a hole in the line rather than closing it up and
            // pretending the week was shorter.
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
                        .stroke(Palette.hairline, lineWidth: 1)
                }

                Path { path in
                    var pen = false
                    for spot in spots {
                        guard let spot else { pen = false; continue }
                        if pen { path.addLine(to: spot) } else { path.move(to: spot); pen = true }
                    }
                }
                .stroke(Palette.brand, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                    if let spot {
                        Circle()
                            .fill(Palette.brand)
                            .frame(width: 7, height: 7)
                            .position(spot)
                    }
                }
            }
        }
    }
}
