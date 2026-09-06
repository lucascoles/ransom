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
    private var earned: Int { steps.minutesFromStepsToday }
    private var cap: Int { plan.stepMinutesCap }

    /// Steps still to walk before the next whole minute lands.
    private var toNextMinute: Int? {
        guard earned < cap else { return nil }
        let perMinute = plan.repsPerMinute(for: .steps)
        guard perMinute > 0 else { return nil }
        return perMinute - (steps.stepsToday % perMinute)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                RexScene(pose: earned >= cap ? .cheer : .walking, line: rexLine, size: 84)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)

                stepsCard
                earnedCard

                if steps.isDenied { permissionCard }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .ransomScreenBackground()
        .task {
            await steps.syncToday(plan: plan)
            steps.startLiveUpdates()
        }
        .onDisappear { steps.stopLiveUpdates() }
    }

    private var stepsCard: some View {
        VStack(spacing: 6) {
            Text(steps.stepsToday.formatted())
                .font(RansomFont.display(56))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(steps.stepsToday)))
            Text("steps today")
                .font(RansomFont.caption(13))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .ransomCard()
    }

    private var earnedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Banked from walking")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(earned) / \(cap) min")
                    .font(RansomFont.headline(15))
                    .foregroundStyle(earned >= cap ? Palette.green : Palette.brand)
            }

            // A bar rather than a number alone: the cap is the point of this
            // screen, and a figure on its own does not say how close it is.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceAlt)
                    Capsule()
                        .fill(earned >= cap ? Palette.green : Palette.brand)
                        .frame(width: geometry.size.width * min(1, Double(earned) / Double(max(cap, 1))))
                }
            }
            .frame(height: 10)

            Text(capLine)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ransomCard()
    }

    private var capLine: String {
        guard earned < cap else {
            return "That's the day's limit from walking. Sets still earn on top of it."
        }
        guard let toNextMinute else {
            return "\(plan.repsPerMinute(for: .steps)) steps to a minute."
        }
        return "\(toNextMinute) more steps for the next minute. \(plan.repsPerMinute(for: .steps)) steps to a minute, up to \(cap) a day."
    }

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
        return "\(earned) minute\(earned == 1 ? "" : "s") banked just for getting about."
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
