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

    var plan: ReppPlan
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
                    RexView(pose: .flex, size: 150)
                        .padding(.top, context == .standalone ? 4 : 24)

                    Text("Repp Pro")
                        .font(ReppFont.display(34))
                        .foregroundStyle(Palette.ink)

                    Text("The whole point of the app.")
                        .font(ReppFont.body(15))
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.top, 2)

                    VStack(spacing: 12) {
                        feature(
                            icon: "lock.shield.fill",
                            title: "Block any app you choose",
                            detail: "Instagram, TikTok, YouTube, games — as many as you like."
                        )
                        feature(
                            icon: "figure.strengthtraining.functional",
                            title: "\(plan.repsPerUnlock) reps buys \(plan.minutesPerUnlock) minutes",
                            detail: "Counted automatically by your phone's sensors."
                        )
                        feature(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Streaks, totals and trends",
                            detail: "Every rep you've ever paid, tracked over time."
                        )
                        feature(
                            icon: "slider.horizontal.3",
                            title: "Tune the difficulty",
                            detail: "Chill to Beast mode. Switch movements whenever."
                        )
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.top, 26)

                    priceCard
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.top, 22)
                }
                .padding(.bottom, 20)
            }

            footer
        }
        .reppScreenBackground()
        .onChange(of: store.isSubscribed) { _, subscribed in
            if subscribed { complete() }
        }
    }

    // MARK: - Pieces

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.green)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.greenSoft))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ReppFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var priceCard: some View {
        VStack(spacing: 6) {
            if let trial = store.trialDescription {
                Pill(text: trial.uppercased(), icon: "gift.fill")
                    .padding(.bottom, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(store.displayPrice)
                    .font(ReppFont.display(38))
                    .foregroundStyle(Palette.ink)
                Text("/ month")
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.inkSoft)
            }

            Text("Cancel anytime in Settings.")
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.green, lineWidth: 2)
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(ReppFont.caption(12))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(
                title: store.trialDescription == nil ? "Subscribe" : "Start free trial",
                isLoading: isWorking
            ) {
                buy()
            }

            HStack(spacing: 18) {
                TextButton(title: "Restore") { restore() }
                Link("Terms", destination: URL(string: "https://repp.app/terms")!)
                    .font(ReppFont.caption(14))
                    .foregroundStyle(Palette.inkSoft)
                Link("Privacy", destination: URL(string: "https://repp.app/privacy")!)
                    .font(ReppFont.caption(14))
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

    // MARK: - Actions

    private func buy() {
        errorMessage = nil
        isWorking = true
        Task {
            let success = await store.purchase()
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
