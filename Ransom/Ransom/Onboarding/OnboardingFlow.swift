import SwiftUI

/// The intake flow: one question per screen, a progress bar that only ever moves
/// forward, and Rex showing up often enough that it feels like a conversation.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(SubscriptionManager.self) private var store

    @State private var draft = UserProfile.launchSeed ?? UserProfile()
    @State private var step: OnboardingStep = OnboardingStep.launchStep ?? .coldOpen
    @State private var history: [OnboardingStep] = []
    /// Lives here, not in the step, so stepping back and forward doesn't wipe a
    /// "no" and re-ask the bedtime question. Only "yes" is recoverable from the
    /// profile, since a "no" writes nothing to `peakTimes`.
    @State private var scrollsInBed: Bool?
    /// Same reason. "Something else" is the one pick on the apps step that writes
    /// nothing to the profile, so kept in the step it was gone after a back tap -
    /// and with it the only thing enabling Continue for someone whose app isn't
    /// in the list.
    @State private var picksOtherApp = false
    @State private var isMovingForward = true

    var body: some View {
        VStack(spacing: 0) {
            if step.showsChrome {
                chrome
            }

            ZStack {
                content
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ransomScreenBackground()
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        // The drop-off funnel: RevenueCat keeps the furthest step each person
        // reached. See `Revenue.markIntakeStep`.
        .onAppear { Revenue.markIntakeStep(step) }
        .onChange(of: step) { _, reached in Revenue.markIntakeStep(reached) }
    }

    // MARK: - Chrome

    private var chrome: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.surfaceAlt))
            }
            .pressable(scale: 0.9)
            .opacity(history.isEmpty ? 0 : 1)
            .disabled(history.isEmpty)

            StepProgressBar(progress: step.progress)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .coldOpen:
            ColdOpenStep(onFinish: { advance(to: .welcome) })

        case .welcome:
            WelcomeStep(onStart: { advance(to: .name) })

        case .name:
            NameStep(profile: $draft, onNext: { advance(to: .apps) })

        case .apps:
            AppsStep(profile: $draft, picksOther: $picksOtherApp, onNext: { advance(to: .scrollLoad) })

        case .scrollLoad:
            ScrollLoadStep(profile: $draft, scrollsInBed: $scrollsInBed, onNext: { advance(to: .reality) })

        case .reality:
            RealityCheckStep(profile: draft, onNext: { advance(to: .age) })

        case .age:
            AgeStep(profile: $draft, onNext: { advance(to: .projection) })

        case .projection:
            ProjectionStep(profile: draft, onNext: { advance(to: .screenGoal) })

        case .screenGoal:
            ScreenGoalStep(profile: $draft, onNext: { advance(to: .identity) })

        case .identity:
            IdentityStep(profile: $draft, onNext: { advance(to: .exercises) })

        case .exercises:
            ExercisesStep(profile: $draft, onNext: { advance(to: .intensity) })

        case .intensity:
            IntensityStep(profile: $draft, onNext: { advance(to: .bank) })

        case .bank:
            BankExplainerStep(profile: draft, onNext: { advance(to: .weight) })

        case .weight:
            WeightStep(profile: $draft, onNext: { advance(to: .blocking) })

        case .blocking:
            BlockingExplainerStep(profile: draft, onNext: { advance(to: .firstRep) })

        case .firstRep:
            FirstRepStep(profile: draft, onNext: { advance(to: .building) })

        case .building:
            BuildingPlanStep(profile: draft, onNext: { advance(to: .plan) })

        case .plan:
            PlanRevealStep(profile: draft, onNext: { advance(to: .paywall) })

        case .paywall:
            PaywallView(
                plan: RansomPlan.make(from: draft),
                context: .onboarding,
                onFinish: finishOnboarding
            )
            // On arrival rather than after a purchase, so the people who leave
            // here carry their answers too and the two groups can be compared.
            .onAppear { Revenue.tag(draft) }
        }
    }

    // MARK: - Navigation

    private func advance(to next: OnboardingStep) {
        // Auto-advancing steps call this once per tap, and a quick double tap
        // got here twice: the second call pushed the destination onto its own
        // history, so the first back tap from the next screen did nothing.
        guard next != step else { return }
        isMovingForward = true
        // The building screen advances itself, so it can never be somewhere to go
        // back to. Recorded, a back tap from the plan replayed the theatre and
        // landed straight back on the plan, and nothing before it was reachable.
        if step != .building {
            history.append(step)
        }
        step = next
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        Haptics.tap()
        isMovingForward = false
        step = previous
    }

    private func finishOnboarding() {
        model.profile = draft
        model.hasCompletedOnboarding = true
        Revenue.markIntakeFinished()
        // Saved first, celebrated second: see `WelcomeCelebration`.
        model.showWelcome = true
        Haptics.success()
    }
}

/// Each screen in the intake, in order. `progress` drives the top bar.
///
/// Fifteen screens. Seven were cut in one pass because each was either saying
/// something a neighbour already said (welcome after the cold open, the
/// projection after the reality check, the bank after the pace step) or asking
/// for something nothing used (age, height and weight). The rating ask went
/// because it sat between the plan and the trial, and asked people to rate an
/// app they had not opened yet. The notifications ask is not in here at all: it
/// comes after the paywall, behind the welcome (see `RootView`), so it never
/// stands between someone and the purchase.
enum OnboardingStep: Int, CaseIterable, Hashable {
    // Three taps naming the problem, before anything is asked for. Ends by
    // turning the story on the reader, which is the whole welcome.
    case coldOpen
    case welcome
    case name
    // The confession comes first: the reality check only lands because the user
    // just named their own apps and their own hours.
    case apps
    case scrollLoad
    case reality
    // Age sits ahead of the projection, not behind it. It used to come four
    // screens later, so the "years of your waking life" figure was computed from
    // the default 24 for every user who had not yet been asked.
    case age
    case projection
    // The goal lands while the cost of the current habit is still on screen.
    case screenGoal
    case identity
    // Calibration sits after the hook, so it reads as building the fix rather
    // than filling in a form.
    case exercises
    case intensity
    // The economy the pace buys into.
    case bank
    // One picker, and skippable. Height used to be asked for here too and was
    // read by nothing; weight scales the calorie estimate, so without it every
    // user gets the figure for an average adult.
    case weight
    // What happens to the apps they named, drawn, with the Screen Time ask on
    // the same screen. Asked here because the pace step has just said what a
    // set is worth, so "your reps open them" is a sentence they can check.
    case blocking
    case firstRep
    case building
    case plan
    // Asked while the plan is still on screen and before any money is mentioned,
    // so it reads as being pleased with what was built rather than as payment.
    case paywall

    var showsChrome: Bool {
        switch self {
        case .coldOpen, .welcome, .building, .paywall, .firstRep: return false
        default: return true
        }
    }

    /// Work already done before the bar appears.
    ///
    /// The cold open is three taps the user has genuinely made, but it shows no
    /// chrome, so without this the bar surfaces at the first question sitting
    /// near zero and the flow reads as though nothing has happened yet.
    /// Crediting what they've actually done is both truer and kinder. The bar
    /// still reaches exactly 100% at the paywall, because the credit is added to
    /// both halves.
    private static let creditBeforeChrome = 1.0

    var progress: Double {
        let total = Double(OnboardingStep.paywall.rawValue) + Self.creditBeforeChrome
        guard total > 0 else { return 0 }
        return (Double(rawValue) + Self.creditBeforeChrome) / total
    }

    /// Opens the app on one named screen instead of the cold open, so a
    /// screenshot run can capture the whole flow without driving the UI:
    ///
    ///     xcrun simctl launch DEVICE com.ransom.app -RansomStartStep identity
    ///
    /// Debug builds only. A release build always starts at `.coldOpen`.
    static var launchStep: OnboardingStep? {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "RansomStartStep") else { return nil }
        return allCases.first { String(describing: $0) == name }
        #else
        return nil
        #endif
    }
}
