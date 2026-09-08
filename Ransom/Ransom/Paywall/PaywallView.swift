import SwiftUI

/// The one place money is asked for. Shown at the end of onboarding and again
/// from Settings if the subscription lapses.
struct PaywallView: View {
    enum Context {
        /// Last step of the intake — the plan has just been revealed.
        case onboarding
        /// Opened later from Settings, so it can be dismissed.
        case standalone
    }

    var plan: RansomPlan
    var context: Context
    var onFinish: () -> Void

    @Environment(SubscriptionManager.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if context == .standalone {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.surfaceAlt))
                    }
                    .pressable(scale: 0.9)
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 8)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Sized so both plan rows sit above the footer on a 6.1" screen
                    // without scrolling: a price you have to scroll to find reads as
                    // a price being hidden.
                    RexImage(pose: .flex, size: 84)
                        .padding(.top, context == .standalone ? 0 : 4)

                    Text("Ransom Pro")
                        .font(RansomFont.display(30))
                        .foregroundStyle(Palette.ink)

                    Text(subtitle)
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.top, 2)

                    VStack(spacing: 10) {
                        feature(
                            icon: "lock.shield.fill",
                            title: "Your apps, your rules",
                            detail: "Instagram, TikTok, games. Pick any app, as many as you like."
                        )
                        feature(
                            icon: plan.exercise.symbol,
                            title: "\(plan.setTarget.formatted()) \(plan.exercise.shortTitle.lowercased()) banks \(Currency.coins(plan.minutesPerUnlock))",
                            detail: "A coin is a minute. Bank them whenever you like, spend them when you want them."
                        )
                        feature(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Every rep counts",
                            detail: "Streaks, lifetime totals, and the hours you got back."
                        )
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 14)

                    // Nothing to quote when the target sits on the baseline. The
                    // plan screen hides its projection for that case; a green
                    // "0h back in month one" here undid that a screen later.
                    if plan.projectedMinutesSavedPerDay > 0 {
                        firstMonthStrip
                            .padding(.horizontal, Metrics.screenPadding)
                            .padding(.top, 12)
                    }

                    planPicker
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, 12)
                }
                .padding(.bottom, 12)
            }

            footer
        }
        .ransomScreenBackground()
        .onChange(of: store.isSubscribed) { _, subscribed in
            if subscribed { complete() }
        }
    }

    // MARK: - Pieces

    /// Echoes back the sentence they chose in the intake. The paywall is the last
    /// place that promise is worth repeating before it costs money.
    private var subtitle: String {
        guard let identity = plan.identity else { return "Move a little. Scroll a little." }
        return "This is how you \(identity.shortForm)."
    }

    /// The plan screen's first-month figures, repeated here in one line. It is the
    /// concrete thing being bought, and the same curve produced both numbers, so
    /// the paywall can't promise anything the plan didn't.
    private var firstMonthStrip: some View {
        HStack(spacing: 0) {
            stat(
                value: "\(Int(plan.firstMonthHoursSaved.rounded()))h",
                label: "back in month one",
                tint: Palette.green
            )
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 30)
            stat(
                value: plan.firstMonthReps.formatted(),
                label: "\(plan.exercise.shortTitle.lowercased()) along the way",
                tint: Palette.brand
            )
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surfaceAlt)
        )
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(RansomFont.title(22))
                .foregroundStyle(tint)
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseIcon(name: icon, size: 15)
                .foregroundStyle(Palette.brand)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.brandSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RansomFont.headline(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(RansomFont.body(13))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Two plans, annual pre-selected. The weekly rate is what makes starting feel
    /// cheap; the annual is what the weekly rate exists to make look reasonable.
    private var planPicker: some View {
        VStack(spacing: 8) {
            planRow(.annual)
            planRow(.weekly)
        }
    }

    private func planRow(_ plan: SubscriptionManager.Plan) -> some View {
        let isSelected = store.selectedPlan == plan
        let isAnnual = plan == .annual

        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                store.selectedPlan = plan
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isSelected ? Palette.brand : Palette.hairline)

                VStack(alignment: .leading, spacing: 3) {
                    // The annual row's headline is the offer itself. "Annual"
                    // describes the billing period, which is the least
                    // interesting thing about it and is said underneath anyway.
                    // One line each, shrinking rather than wrapping. A plan row
                    // is scanned in a second and compared against the row below
                    // it; a headline that wraps pushes the rows out of step and
                    // makes the pair harder to read than either line was long.
                    Text(isAnnual ? annualHeadline : plan.title)
                        .font(RansomFont.headline(17))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(isAnnual ? annualSubtitle : weeklySubtitle)
                        .font(RansomFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                // Both plans priced per week, which is the only comparison that
                // does any work: $0.96 against $4.99 is the argument for the
                // annual plan, made at a glance and needing no arithmetic.
                //
                // The annual's real charge is $49.99 once a year and the subtitle
                // states it plainly. Putting that figure here would sit "$49.99"
                // directly above "$4.99" and make the yearly plan look ten times
                // the price of the weekly one.
                VStack(alignment: .trailing, spacing: 1) {
                    Text(isAnnual ? (store.annualPerWeek ?? store.displayPrice(for: plan))
                                  : store.displayPrice(for: plan))
                        .font(RansomFont.title(20))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("/ week")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.brandSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.brand : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .pressable(scale: 0.985)
    }

    /// "Start free and save 81%". The two reasons to pick this row, in the line
    /// the eye lands on first.
    private var annualHeadline: String {
        let free = store.trialDescription(for: .annual) != nil
        guard let saving = store.annualSavingsPercent else {
            return free ? "Start free" : "Best value"
        }
        // "and" was the only word here doing no work, and it was the one pushing
        // this onto a second line.
        return free ? "Start free, save \(saving)%" : "Save \(saving)%"
    }

    private var annualSubtitle: String {
        // The trial leads, because it is the part that decides whether anyone
        // taps at all. Both products carry the same three days free, but only the
        // weekly row ever said so - so the annual plan looked like the one where
        // you pay up front, which is the opposite of the truth and was quietly
        // pushing people onto the worse-value option.
        // The headline sells; this states what is actually charged and when, so
        // nobody reaches the App Store sheet and meets a number they have not
        // already seen.
        "\(store.displayPrice(for: .annual)) billed annually"
    }

    /// No trial on this one by design, so it says what it costs and nothing else.
    private var weeklySubtitle: String { "Billed every week" }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
            }

            // The line the trial-reminder screen just made, repeated where the
            // price is. Only when there is a trial to make it true of.
            if store.trialDescription(for: store.selectedPlan) != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.green)
                    Text("No payment due now")
                        .font(RansomFont.headline(14))
                        .foregroundStyle(Palette.ink)
                }
            }

            PrimaryButton(title: ctaTitle, isLoading: isWorking) {
                buy()
            }

            // Price, term and renewal, spelled out. Required, and the honest thing
            // to do next to a weekly rate.
            Text(store.disclosure(for: store.selectedPlan))
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                TextButton(title: "Restore") { restore() }
                Link("Terms", destination: RansomLinks.terms)
                    .font(RansomFont.caption(14))
                    .foregroundStyle(Palette.inkSoft)
                Link("Privacy", destination: RansomLinks.privacy)
                    .font(RansomFont.caption(14))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 18)
        .padding(.top, 6)
        .background(
            Palette.canvas
                .shadow(color: .black.opacity(0.05), radius: 12, y: -6)
                .ignoresSafeArea()
        )
    }

    private var ctaTitle: String {
        store.trialDescription(for: store.selectedPlan) == nil ? "Subscribe" : "Start free trial"
    }

    // MARK: - Actions

    private func buy() {
        errorMessage = nil
        isWorking = true
        Task {
            let plan = store.selectedPlan
            // Read before the purchase: the answer flips to "no" once it goes
            // through, and a reminder about a trial that never started is worse
            // than none.
            let startsTrial = await store.isEligibleForTrial(plan)
            let success = await store.purchase(plan)
            isWorking = false
            if success {
                // The promise the trial-reminder screen made, kept.
                if startsTrial, let days = store.trialDays(for: plan) {
                    NotificationManager.scheduleTrialEndingReminder(trialDays: days)
                }
                complete()
            } else if case .failed(let message) = store.purchaseState {
                errorMessage = message
            }
        }
    }

    private func restore() {
        errorMessage = nil
        isWorking = true
        Task {
            await store.restore()
            isWorking = false
            if store.isSubscribed {
                complete()
            } else if case .failed(let message) = store.purchaseState {
                errorMessage = message
            }
        }
    }

    private func complete() {
        model.isSubscribed = true
        Haptics.success()
        switch context {
        case .onboarding: onFinish()
        case .standalone: dismiss()
        }
    }
}
