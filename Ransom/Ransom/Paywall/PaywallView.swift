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
                    RexImage(pose: .flex, size: 104)
                        .padding(.top, context == .standalone ? 2 : 10)

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
                            title: "Block any app you choose",
                            detail: "Instagram, TikTok, games — as many as you like."
                        )
                        feature(
                            icon: "figure.strengthtraining.functional",
                            title: "\(plan.repsPerUnlock) reps buys \(plan.minutesPerUnlock) minutes",
                            detail: "The price rises the more you come back."
                        )
                        feature(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Every rep you've ever paid",
                            detail: "Lifetime totals, streaks and hours saved."
                        )
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 16)

                    planPicker
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, 16)
                }
                .padding(.bottom, 20)
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
        guard let identity = plan.identity else { return "The whole point of the app." }
        return "Keep being \(identity.shortForm)."
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.green)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.greenSoft))

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
                    .foregroundStyle(isSelected ? Palette.green : Palette.hairline)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(RansomFont.headline(17))
                            .foregroundStyle(Palette.ink)

                        if isAnnual, let saving = store.annualSavingsPercent {
                            Pill(text: "SAVE \(saving)%", tint: Palette.onGreen, background: Palette.green)
                        }
                    }

                    Text(isAnnual ? annualSubtitle : weeklySubtitle)
                        .font(RansomFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.displayPrice(for: plan))
                        .font(RansomFont.title(20))
                        .foregroundStyle(Palette.ink)
                    Text("/ \(plan.periodLabel)")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.greenSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.green : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .pressable(scale: 0.985)
    }

    private var annualSubtitle: String {
        if let perWeek = store.annualPerWeek {
            return "Works out at \(perWeek) a week"
        }
        return "Billed once a year"
    }

    private var weeklySubtitle: String {
        store.trialDescription(for: .weekly).map { "\($0), then billed weekly" } ?? "Billed every week"
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
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
                Link("Terms", destination: URL(string: "https://ransom.app/terms")!)
                    .font(RansomFont.caption(14))
                    .foregroundStyle(Palette.inkSoft)
                Link("Privacy", destination: URL(string: "https://ransom.app/privacy")!)
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
