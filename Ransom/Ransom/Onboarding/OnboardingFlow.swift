import SwiftUI

/// The intake flow: one question per screen, a progress bar that only ever moves
/// forward, and Rex showing up often enough that it feels like a conversation.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime

    @State private var draft = UserProfile()
    @State private var step: OnboardingStep = .welcome
    @State private var history: [OnboardingStep] = []
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
        case .welcome:
            WelcomeStep(onStart: { advance(to: .name) })

        case .name:
            NameStep(profile: $draft, onNext: { advance(to: .gender) })

        case .gender:
            GenderStep(profile: $draft, onNext: { advance(to: .age) })

        case .age:
            AgeStep(profile: $draft, onNext: { advance(to: .body) })

        case .body:
            BodyStep(profile: $draft, onNext: { advance(to: .fitness) })

        case .fitness:
            FitnessStep(profile: $draft, onNext: { advance(to: .apps) })

        case .apps:
            AppsStep(profile: $draft, onNext: { advance(to: .scrollLoad) })

        case .scrollLoad:
            ScrollLoadStep(profile: $draft, onNext: { advance(to: .reality) })

        case .reality:
            RealityCheckStep(profile: draft, onNext: { advance(to: .goals) })

        case .goals:
            GoalsStep(profile: $draft, onNext: { advance(to: .exercises) })

        case .exercises:
            ExercisesStep(profile: $draft, onNext: { advance(to: .intensity) })

        case .intensity:
            IntensityStep(profile: $draft, onNext: { advance(to: .peakTimes) })

        case .peakTimes:
            PeakTimesStep(profile: $draft, onNext: { advance(to: .notifications) })

        case .notifications:
            NotificationsStep(onNext: { advance(to: .referral) })

        case .referral:
            ReferralStep(profile: $draft, onNext: { advance(to: .socialProof) })

        case .socialProof:
            SocialProofStep(onNext: { advance(to: .building) })

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
    case welcome
    case name
    case gender
    case age
    case body
    case fitness
    case apps
    case scrollLoad
    case reality
    case goals
    case exercises
    case intensity
    case peakTimes
    case notifications
    case referral
    case socialProof
    case building
    case plan
    case paywall

    var showsChrome: Bool {
        switch self {
        case .welcome, .building, .paywall: return false
        default: return true
        }
    }

    var progress: Double {
        let total = Double(OnboardingStep.paywall.rawValue)
        guard total > 0 else { return 0 }
        return Double(rawValue) / total
    }
}
