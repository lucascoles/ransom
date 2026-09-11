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
                    // The billing period, plainly. This used to be the offer
                    // itself - "Start free, save 81%" - which is a pricing claim,
                    // and pricing claims are exactly what guideline 3.1.2(c)
                    // requires to sit *below* the amount charged.
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(RansomFont.headline(17))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        // The saving still gets said, as a badge rather than as
                        // the headline. A percentage is calculated pricing, so it
                        // may sit beside the plan name but not above the charge.
                        if isAnnual, let saving = store.annualSavingsPercent {
                            Text("SAVE \(saving)%")
                                .font(RansomFont.caption(10))
                                .foregroundStyle(Palette.onBrand)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.brand))
                        }
                    }

                    Text(isAnnual ? annualSubtitle : weeklySubtitle)
                        .font(RansomFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Calculated pricing, kept deliberately small and faint. It
                    // is the argument for the annual plan, but it is not what
                    // anybody is charged, so it may not outrank the figure that
                    // is.
                    if isAnnual, let perWeek = store.annualPerWeek {
                        Text("Works out at \(perWeek) per week")
                            .font(RansomFont.caption(11))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 4)

                // **The amount actually charged, and the largest thing in the
                // row.** This slot used to hold the per-week figure at 20pt with
                // the real charge stated underneath at 13pt, on the reasoning
                // that "$49.99" above "$4.99" made the yearly plan look six times
                // the price of the weekly one. It does - and App Review rejected
                // build 5 for it under guideline 3.1.2(c), which requires the
                // billed amount to be the most clear and conspicuous pricing
                // element, with trials, introductory pricing and calculated
                // per-week figures subordinate in position and size.
                //
                // The comparison the per-week figure was making still gets made,
                // one line down and two sizes smaller, which is where a number
                // nobody is charged belongs.
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.displayPrice(for: plan))
                        .font(RansomFont.title(22))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isAnnual ? "per year" : "per week")
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

    /// States the trial only when this user can actually have it.
    ///
    /// The weekly plan carries no introductory offer at all, and even on the
    /// annual one an offer exists on the product for everybody while only
    /// first-time subscribers are eligible to use it. Saying "3 days free" to
    /// somebody who is about to be charged immediately is the misrepresentation
    /// 3.1.2(c) is about, so this asks `store` whether the offer is live for
    /// this account rather than whether it exists.
    private var annualSubtitle: String {
        if let trial = store.trialDescription(for: .annual) {
            return "\(trial), then billed yearly"
        }
        return "Billed yearly"
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

            // Said next to the price, and only when there is a trial to make it
            // true of. Now the only place the trial is spelled out before the
            // button, so it earns its keep twice over.
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
            let success = await store.purchase(store.selectedPlan)
            isWorking = false
            if success {
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
