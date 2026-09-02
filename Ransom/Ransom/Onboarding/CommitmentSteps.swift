import SwiftUI

// MARK: - Identity

/// Replaces the old goals checklist.
///
/// Six checkboxes generated data nobody used and no feeling. One first-person
/// sentence the user has to agree is about them is a different object entirely —
/// and unlike the checklist, this one is quoted back on the plan screen and the
/// paywall, which is the only thing that makes it worth a screen.
struct IdentityStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Finish the sentence",
            subtitle: "Pick the one that's most true. Rex will hold you to it.",
            showsButton: false,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Identity.allCases) { identity in
                    ChoiceCard(
                        title: identity.statement,
                        emoji: identity.emoji,
                        isSelected: profile.identity == identity
                    ) {
                        profile.identity = identity
                        AutoAdvance.after(onNext)
                    }
                }
            }
        }
    }
}

// MARK: - First rep

/// The only screen in the funnel where the user moves.
///
/// Everything before this is a form; the plan that follows is a forecast. Doing
/// five push-ups on the floor turns it into an extrapolation of something they
/// actually did, and it surfaces a broken sensor before the charge rather than
/// after it.
///
/// Deliberately not gated: the skip path is one line, no scolding. A funnel that
/// punishes you for not doing push-ups in a shop doorway deserves the uninstall.
struct FirstRepStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @State private var reps = 0
    @State private var isCounting = false
    @State private var finished = false

    private let target = 5
    private var plan: RansomPlan { RansomPlan.make(from: profile) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexImage(pose: finished ? .cheer : (isCounting ? .pushUp(down: reps % 2 == 1) : .coach), size: 150)

            if !isCounting && !finished {
                intro
            } else if finished {
                payoff
            } else {
                counter
            }

            Spacer()

            footer
        }
        .padding(.horizontal, Metrics.screenPadding)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCounting)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: finished)
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Text("Five. Right now.")
                .font(RansomFont.title(28))
                .foregroundStyle(Palette.ink)
            Text("Not for scroll time. Just so we both know you can.")
                .font(RansomFont.body(16))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private var counter: some View {
        VStack(spacing: 6) {
            Text("\(reps)")
                .font(RansomFont.counter(84))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(reps)))
            Text("of \(target)")
                .font(RansomFont.headline(18))
                .foregroundStyle(Palette.inkSoft)
            Text("Phone on the floor. We'll wait.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private var payoff: some View {
        VStack(spacing: 10) {
            Text("That's one.")
                .font(RansomFont.title(28))
                .foregroundStyle(Palette.ink)
            Text("There's about \(plan.projectedRepsRounded.formatted()) more in a year of you.")
                .font(RansomFont.body(16))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if finished {
                PrimaryButton(title: "Build my plan", action: onNext)
            } else if isCounting {
                PrimaryButton(title: reps >= target ? "Done" : "Count a rep") {
                    if reps >= target {
                        finished = true
                        Haptics.celebrate()
                    } else {
                        reps += 1
                        Haptics.rep()
                        if reps >= target {
                            finished = true
                            Haptics.celebrate()
                        }
                    }
                }
            } else {
                PrimaryButton(title: "I'm on the floor") {
                    isCounting = true
                    Haptics.tap()
                }
                // No scolding on the way past. The floor is still there later.
                TextButton(title: "Not here") { onNext() }
            }
        }
        .padding(.bottom, 28)
    }
}
