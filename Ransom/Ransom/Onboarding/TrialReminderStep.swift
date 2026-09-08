import SwiftUI

// MARK: - Trial reminder

/// The screen before the paywall, answering the one question people bring to a
/// money screen: will I get charged without noticing.
///
/// It does three jobs in one place. It promises the reminder, in Rex's voice,
/// with the real trial length off StoreKit. It asks for notification permission,
/// which used to have its own screen earlier in the flow and no reason attached
/// beyond "Rex will ping you"; here the permission is what makes the promise
/// keepable, and the subtitle says so. And it puts "No payment due now" and a
/// "Continue for FREE" button in front of the paywall, so the trial is already
/// framed as free before a price is on screen.
///
/// The promise is real: `PaywallView` schedules
/// `NotificationManager.scheduleTrialEndingReminder` when a purchase starts a
/// trial, the day before it ends.
struct TrialReminderStep: View {
    var onNext: () -> Void

    @Environment(SubscriptionManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRequesting = false
    @State private var rang = false

    private var trialDays: Int {
        store.trialDays(for: store.selectedPlan) ?? SubscriptionManager.Plan.fallbackTrialDays
    }

    /// The day the reminder lands, counted the way a person counts a trial:
    /// day one is today.
    private var reminderDay: Int { max(1, trialDays - 1) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            bell

            VStack(spacing: 12) {
                Text("Rex will remind you before your trial ends")
                    .font(RansomFont.title(28))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(trialDays) days free. On day \(reminderDay) you get a heads-up. Not for you? Cancel, and nothing is charged.")
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)

                Text("As long as notifications are on. Rex asks for that next.")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.top, 30)
            .padding(.horizontal, Metrics.screenPadding)

            Spacer()

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.green)
                    Text("No payment due now")
                        .font(RansomFont.headline(16))
                        .foregroundStyle(Palette.ink)
                }

                PrimaryButton(title: "Continue for FREE", isLoading: isRequesting, action: proceed)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.35)) { rang = true }
            }
        }
    }

    /// A bell with one thing waiting on it. The badge is the picture of the
    /// promise: one reminder, not a stream.
    private var bell: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Palette.brandSoft)
                .frame(width: 168, height: 168)

            Image(systemName: "bell.fill")
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(Palette.brand)
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(rang ? 0 : -14), anchor: .top)

            Text("1")
                .font(RansomFont.counter(17))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.danger))
                .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 3))
                .offset(x: -18, y: 22)
                .scaleEffect(rang || reduceMotion ? 1 : 0.01)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A bell with one reminder waiting")
    }

    /// Ask for notifications only if nobody has yet. iOS shows the prompt once
    /// per install, so a second request would silently do nothing and the
    /// button would look broken. Either way the flow moves on.
    private func proceed() {
        isRequesting = true
        Task {
            if await NotificationManager.isPermissionUndetermined() {
                await NotificationManager.requestPermission()
            }
            isRequesting = false
            onNext()
        }
    }
}
