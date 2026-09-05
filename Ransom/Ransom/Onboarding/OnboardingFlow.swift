import SwiftUI

/// The intake flow: one question per screen, a progress bar that only ever moves
/// forward, and Rex showing up often enough that it feels like a conversation.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime

    @State private var draft = UserProfile.launchSeed ?? UserProfile()
    @State private var step: OnboardingStep = OnboardingStep.launchStep ?? .coldOpen
    @State private var history: [OnboardingStep] = []
    /// Lives here, not in the step, so stepping back and forward doesn't wipe a
    /// "no" and re-ask the bedtime question. Only "yes" is recoverable from the
    /// profile, since a "no" writes nothing to `peakTimes`.
    @State private var scrollsInBed: Bool?
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
            AppsStep(profile: $draft, onNext: { advance(to: .scrollLoad) })

        case .scrollLoad:
            ScrollLoadStep(profile: $draft, scrollsInBed: $scrollsInBed, onNext: { advance(to: .reality) })

        case .reality:
            RealityCheckStep(profile: draft, onNext: { advance(to: .projection) })

        case .projection:
            ProjectionStep(profile: draft, onNext: { advance(to: .screenGoal) })

        case .screenGoal:
            ScreenGoalStep(profile: $draft, onNext: { advance(to: .identity) })

        case .identity:
            IdentityStep(profile: $draft, onNext: { advance(to: .age) })

        case .age:
            AgeStep(profile: $draft, onNext: { advance(to: .body) })

        case .body:
            BodyStep(profile: $draft, onNext: { advance(to: .exercises) })


        case .exercises:
            ExercisesStep(profile: $draft, onNext: { advance(to: .intensity) })

        case .intensity:
            IntensityStep(profile: $draft, onNext: { advance(to: .bank) })

        case .bank:
            BankExplainerStep(profile: draft, onNext: { advance(to: .firstRep) })

        case .firstRep:
            FirstRepStep(profile: draft, onNext: { advance(to: .notifications) })

        case .notifications:
            NotificationsStep(onNext: { advance(to: .building) })

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
        }
    }

    // MARK: - Navigation

    private func advance(to next: OnboardingStep) {
        isMovingForward = true
        history.append(step)
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
        Haptics.success()
    }
}

/// Each screen in the intake, in order. `progress` drives the top bar.
enum OnboardingStep: Int, CaseIterable, Hashable {
    // Three taps naming the problem, before anything is asked for.
    case coldOpen
    case welcome
    case name
    // The confession comes first: the reality check only lands because the user
    // just named their own apps and their own hours.
    case apps
    case scrollLoad
    case reality
    // The number that changes the room, straight after they've named their hours.
    case projection
    // The goal lands while the cost of the current habit is still on screen.
    case screenGoal
    case identity
    // Calibration sits after the hook, so it reads as building the fix rather
    // than filling in a form.
    case age
    case body
    case exercises
    case intensity
    // The economy the pace buys into. The commitment itself now lives on the
    // pace step, since a tier and its run are one decision.
    case bank
    case firstRep
    // Asking here, right after they've earned something, is the one moment the
    // permission reads as Rex keeping his side of the deal rather than a tax.
    case notifications
    case building
    case plan
    case paywall

    var showsChrome: Bool {
        switch self {
        case .coldOpen, .welcome, .building, .paywall, .firstRep: return false
        default: return true
        }
    }

    /// Work already done before the bar appears.
    ///
    /// The cold open is three taps the user has genuinely made, and the welcome
    /// screen a fourth — but neither shows chrome, so without this the bar surfaces
    /// at the first question sitting near zero and the flow reads as though nothing
    /// has happened yet. Crediting what they've actually done is both truer and
    /// kinder: the first bar lands around a sixth of the way along instead of a
    /// tenth. Raise it to flatter harder; the bar still reaches exactly 100% at the
    /// paywall either way, because the credit is added to both halves.
    private static let creditBeforeChrome = 1.0

    var progress: Double {
        let total = Double(OnboardingStep.paywall.rawValue) + Self.creditBeforeChrome
        guard total > 0 else { return 0 }
        return (Double(rawValue) + Self.creditBeforeChrome) / total
    }

    /// Opens the app on one named screen instead of the welcome step, so a
    /// screenshot run can capture the whole flow without driving the UI:
    ///
    ///     xcrun simctl launch DEVICE com.ransom.app -RansomStartStep identity
    ///
    /// Debug builds only — a release build always starts at `.welcome`.
    static var launchStep: OnboardingStep? {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "RansomStartStep") else { return nil }
        return allCases.first { String(describing: $0) == name }
        #else
        return nil
        #endif
    }
}
