import SwiftUI

/// Walking, on its own tab.
///
/// It earns differently from everything else in the app and it earns whether or
/// not anybody opens this screen, so it does not belong on Home beside a button
/// that asks you to do something. There is nothing to start here - the phone has
/// been counting all day - which is exactly why it reads as a report rather than
/// a control.
struct StepsView: View {
    @Environment(AppModel.self) private var model
    @State private var steps = StepTracker()

    private var plan: RansomPlan { model.plan }
    private var earned: Int { steps.minutesEarnedToday(plan: plan) }
    private var cap: Int { plan.stepMinutesCap }
    private var goal: Int { RansomPlan.cappedSteps }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // The same lit plate Home uses. He's the only thing above the first
                // card here, so the ground carries on its own what it shares with
                // the greeting over there.
                HomeMasthead {
                    RexScene(
                        pose: earned >= cap ? .cheer : .walking,
                        line: rexLine,
                        size: 100,
                        grounded: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, -Metrics.screenPadding)

                stepsCard
                statsRow
                StepWeekCard(week: steps.week, goal: goal)

                if steps.isDenied { permissionCard }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .ransomAmbientBackground()
        .task {
            await steps.syncToday(plan: plan)
            await steps.loadWeek()
            steps.startLiveUpdates()
        }
        // Banking again whenever the count moves, not just on the way in.
        // The first visit asks for motion access, and the query that opened
        // this screen has already returned nothing by the time anybody taps
        // Allow - so the one sync on appear banked nothing and the screen sat
        // on zero minutes next to a step counter that had filled itself in.
        // Syncing is idempotent, so a walk in progress simply pays as it goes.
        .onChange(of: steps.stepsToday) { _, _ in
            Task { await steps.syncToday(plan: plan) }
        }
        .onDisappear { steps.stopLiveUpdates() }
    }

    // MARK: - Today

    private var stepsCard: some View {
        VStack(spacing: 6) {
            Text(steps.stepsToday.formatted())
                .font(RansomFont.display(56))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(steps.stepsToday)))
            Text("steps today")
                .font(RansomFont.caption(13))
                .foregroundStyle(Palette.inkSoft)

            goalBar
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .ransomCard()
    }

    /// Progress toward the day's ten thousand.
    ///
    /// Drawn against the step goal, not against the minutes ceiling it happens to
    /// coincide with. The card that used to sit below filled a bar toward "30
    /// min" - a cap reached before lunch, drawn as a target, which made the day's
    /// job look like hitting the limit on earnings. Ten thousand steps is a goal
    /// somebody might actually want to reach.
    private var goalBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let fraction = min(1, Double(steps.stepsToday) / Double(max(goal, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceAlt)
                    Capsule()
                        .fill(fraction >= 1 ? Palette.green : Palette.brand)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(goalLine)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 4)
    }

    private var goalLine: String {
        let remaining = goal - steps.stepsToday
        guard remaining > 0 else { return "\(goal.formatted()) steps. That's the day done." }
        return "\(remaining.formatted()) to go for \(goal.formatted())"
    }

    /// What today's walking paid in, what the bank actually holds, and how far it
    /// was. Distance earns nothing and is here anyway - it is the part of a walk
    /// that people recognise as the walk.
    ///
    /// The first two are deliberately separate figures. Walking earnings only
    /// ever go up, while the bank goes down every time anything is spent from
    /// it, so showing the earnings alone under the word "banked" meant this
    /// screen claimed 32 minutes while the bank held 47 of a different 107 - and
    /// the mismatch read as minutes quietly going missing.
    private var statsRow: some View {
        HStack(spacing: 12) {
            stat(value: "\(earned)", unit: "minutes earned from steps", tint: Palette.brand)
            stat(value: "\(model.bankedMinutes)", unit: "in the bank", tint: Palette.ink)
            stat(value: distanceValue ?? "-", unit: distanceUnit, tint: Palette.ink)
        }
    }

    private func stat(value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(RansomFont.display(26))
                .foregroundStyle(tint)
                // Never wrapped. "2.9km" is one token to a reader and two to the
                // layout engine, so a tile a few points too narrow broke it after
                // the digits and stranded the "m" on a line of its own.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                // Two lines, reserved on every tile whether or not it needs the
                // second. A third of the width does not hold "minutes earned from
                // steps" on one line, and letting only that tile grow left the
                // three cards at different heights.
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .ransomCard()
    }

    /// Split from its unit so the number can carry the display face and the unit
    /// can sit under it like the stat beside it. Locale decides between
    /// kilometres and miles; `.road` is the usage that knows.
    private var measuredDistance: Measurement<UnitLength>? {
        guard let metres = steps.metresToday, metres > 0 else { return nil }
        return Measurement(value: metres, unit: .meters)
    }

    private var distanceValue: String? {
        measuredDistance?.formatted(
            .measurement(width: .narrow, usage: .road,
                         numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }

    private var distanceUnit: String {
        measuredDistance == nil ? "no distance" : "covered"
    }

    // MARK: - Rex

    private var rexLine: String {
        if steps.isDenied {
            return "I can't see your steps. Motion access is off in Settings."
        }
        if earned >= cap {
            return "You've maxed out walking for today. Nice legs."
        }
        if steps.stepsToday == 0 {
            return "Nothing yet today. Your phone counts these whether I'm open or not."
        }
        // A first minute that hasn't landed yet is the one moment the count is
        // moving and the bank isn't, which looks broken unless it is named.
        if earned == 0 {
            let toGo = max(0, plan.repsPerMinute(for: .steps) - steps.stepsToday)
            return "\(toGo) more steps and that's your first minute."
        }
        return "\(earned) minute\(earned == 1 ? "" : "s") earned just for getting about."
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Motion access is off", systemImage: "figure.walk")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)
            Text("Ransom reads the step count your phone already keeps. Turn Motion & Fitness back on in iOS Settings and this fills in.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.brandSoft)
        )
    }
}
