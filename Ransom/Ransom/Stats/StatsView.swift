import SwiftUI

/// The progress tab. Everything the user has done, and what it got them back.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    private enum Window: String, CaseIterable, Identifiable {
        case week, month, allTime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week:    return "7 days"
            case .month:   return "30 days"
            case .allTime: return "All time"
            }
        }
        var days: Int? {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .allTime: return nil
            }
        }
    }

    @State private var window: Window = .week

    private var records: [WorkoutRecord] {
        guard let days = window.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return model.history
        }
        return model.history.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                lifetimeCard
                    .padding(.top, 4)

                ScreenTimeReportCard()

                SegmentPicker(
                    options: Window.allCases.map { (value: $0, label: $0.title) },
                    selection: $window
                )

                headlineCard

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    stat(value: "\(totalReps)", label: "reps done", icon: model.profile.primaryExercise.symbol, tint: Palette.brand)
                    stat(value: "\(Int(totalCalories))", label: "calories", icon: "flame.fill", tint: Palette.flame)
                    stat(value: "\(records.count)", label: "sets", icon: "checkmark.seal.fill", tint: Palette.brand)
                    stat(value: hoursEarned, label: "unlocked", icon: "lock.open.fill", tint: Palette.green)
                }

                // An empty history already has a Rex line and a streak card saying
                // so; two more empty boxes underneath would just be scolding.
                if !model.history.isEmpty {
                    breakdownCard
                    recentCard
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .debugScrollAnchor()
        .ransomScreenBackground()
    }

    // MARK: - Derived

    private var totalReps: Int { records.reduce(0) { $0 + $1.reps } }
    private var totalCalories: Double { records.reduce(0) { $0 + $1.calories } }
    private var totalMinutes: Int { records.reduce(0) { $0 + $1.minutesGranted } }

    private var hoursEarned: String {
        totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
    }

    /// Reps grouped by movement, biggest first.
    private var breakdown: [(exercise: Exercise, reps: Int)] {
        Dictionary(grouping: records, by: \.exercise)
            .map { (exercise: $0.key, reps: $0.value.reduce(0) { $0 + $1.reps }) }
            .sorted { $0.reps > $1.reps }
    }

    // MARK: - Sections

    /// The two numbers people actually stay subscribed for: reps done, time back.
    private var lifetimeCard: some View {
        VStack(spacing: 16) {
            Text("LIFETIME")
                .font(RansomFont.caption(11))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)

            // Reps alone. The other half of this row was lifetime minutes
            // earned, which is a count of scroll time bought - true, but a
            // strange thing to celebrate on the screen that is meant to show the
            // habit shrinking. Reps are the part that only goes one way.
            VStack(spacing: 2) {
                Text(model.lifetimeReps, format: .number)
                    .font(RansomFont.display(56))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(model.lifetimeReps)))
                Text("reps")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)

            savedDerivation

            RexScene(
                pose: model.lifetimeReps > 500 ? .flex : .coach,
                line: lifetimeLine,
                size: 92
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .ransomCard()
    }

    private var lifetimeLine: String {
        let reps = model.lifetimeReps
        if reps == 0 {
            return "No sets yet. The first one is the hard one, and it's a short one."
        }
        return "\(reps.formatted()) reps you wouldn't have done otherwise. I counted every one."
    }

    /// Today, against the day they described when they signed up.
    ///
    /// This used to claim a lifetime saving, worked out by multiplying the stated
    /// baseline across every day installed and subtracting minutes *earned* -
    /// which is what was banked, not what was used. It could read "31m now"
    /// beside a real screen time of three and a half hours, on the same screen.
    /// Today is the only span that can be measured, so today is the only one
    /// claimed, and the figure it uses is the one the card underneath shows.
    private var savedDerivation: some View {
        let baseline = model.baselineMinutes
        let today = model.todayScreenMinutes
        let widest = max(baseline, today, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("TODAY")
                .font(RansomFont.caption(11))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)

            derivationBar(label: "Before Ransom", minutes: baseline, widest: widest, tint: Palette.inkFaint)
            derivationBar(label: "In your apps", minutes: today, widest: widest,
                          tint: today <= baseline ? Palette.green : Palette.danger)

            Text(model.minutesBackToday > 0
                 ? "\(minutes(model.minutesBackToday)) back so far today"
                 : "Past your old average for today")
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(.top, 4)
    }

    private func derivationBar(label: String, minutes value: Int, widest: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 78, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceAlt)
                    // Clamped: on a day that beat the old baseline the bar
                    // would otherwise run past its own track.
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geo.size.width * min(1, Double(value) / Double(widest))))
                }
            }
            .frame(height: 10)

            Text(minutes(value))
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func minutes(_ value: Int) -> String {
        let v = max(0, value)
        return v >= 60 ? "\(v / 60)h \(v % 60)m" : "\(v)m"
    }

    private var headlineCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                RexImage(pose: model.streak > 2 ? .cheer : .idle, size: 92, isAlive: false)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.streak == 0 ? "No streak yet" : "\(model.streak) day streak")
                            .font(RansomFont.title(24))
                            .foregroundStyle(Palette.ink)
                        if model.bestStreak > model.streak {
                            Pill(
                                text: "best \(model.bestStreak)",
                                icon: "trophy.fill",
                                tint: Palette.flame,
                                background: Palette.flameSoft
                            )
                        }
                    }
                    Text(streakLine)
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            WeekBars(values: model.weekBars)
        }
        .ransomCard()
    }

    private var streakLine: String {
        switch model.streak {
        case 0:  return "One set today starts it."
        case 1:  return "Day one. Come back tomorrow and it's a streak."
        case 2...6: return "\(model.streak) days in a row. This is how habits start."
        default: return "\(model.streak) days straight and \(model.totalReps.formatted()) reps all time. That's real."
        }
    }

    private func stat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(RansomFont.title(26))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .ransomCard(padding: 16, radius: 20)
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By move")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            if breakdown.isEmpty {
                Text("No sets in this range.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(breakdown, id: \.exercise) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.exercise.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.brand)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Palette.brandSoft))

                        Text(item.exercise.title)
                            .font(RansomFont.body(15))
                            .foregroundStyle(Palette.ink)

                        Spacer()

                        Text("\(item.reps)")
                            .font(RansomFont.headline(16))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .ransomCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sets")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            ForEach(model.history.suffix(6).reversed()) { record in
                HStack(spacing: 12) {
                    Text(record.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 96, alignment: .leading)

                    Text("\(record.reps) \(record.exercise.shortTitle.lowercased())")
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.ink)

                    Spacer()

                    if record.minutesGranted > 0 {
                        Pill(text: "+\(record.minutesGranted)m")
                    } else {
                        Pill(text: "stopped early", tint: Palette.inkSoft, background: Palette.surfaceAlt)
                    }
                }
            }
        }
        .ransomCard()
    }
}
