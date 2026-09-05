import SwiftUI

// MARK: - Identity

/// Replaces the old goals checklist.
///
/// Six checkboxes generated data nobody used and no feeling. One short goal in the
/// user's own words is a different object: it is quoted back on the plan screen and
/// on the paywall, which is the only thing that makes it worth a screen. Keep the
/// options one line each. The long version of this screen read like a personality
/// quiz and nobody finished the sentences.
struct IdentityStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "What are we going for?",
            subtitle: "Pick the one that matters most. Rex keeps it in mind.",
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
/// five reps on the spot turns it into an extrapolation of something they actually
/// did, and it surfaces a broken sensor before the charge rather than after it.
///
/// The movement is whatever they picked on the exercises step, so the coaching cue,
/// the pose and the button all read off `profile.primaryExercise`. Quoting push-ups
/// at someone who chose squats is the fastest way to look like a template.
///
/// Deliberately not gated: the skip path is one line, no scolding. A funnel that
/// punishes you for not doing push-ups in a shop doorway deserves the uninstall.
struct FirstRepStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @State private var counter: PoseRepCounter
    @State private var finished = false
    @State private var isCounting = false

    private static let target = 5
    private var plan: RansomPlan { RansomPlan.make(from: profile) }
    /// What the demo set will be. Starts at whatever they picked earlier and can
    /// be changed here, because this is the first time the choice stops being
    /// abstract - the floor is in front of them and they can feel which one they
    /// are actually willing to do right now.
    @State private var exercise: Exercise

    init(profile: UserProfile, onNext: @escaping () -> Void) {
        self.profile = profile
        self.onNext = onNext
        _exercise = State(initialValue: profile.primaryExercise)
        _counter = State(initialValue: PoseRepCounter(exercise: profile.primaryExercise,
                                                      target: FirstRepStep.target))
    }

    private var target: Int { FirstRepStep.target }
    private var reps: Int { counter.reps }

    /// The camera is up and has something to show. When it isn't — permission
    /// refused, or no camera — the screen falls back to Rex and taps, exactly as
    /// the set screen does, so the intake never dead-ends.
    private var cameraIsLive: Bool {
        isCounting && !counter.isBlocked && counter.tracking != .idle
    }

    /// Rex only has push-up frames, so he mimes along for push-ups and coaches for
    /// everything else rather than doing the wrong movement on screen.
    private var pose: RexPose {
        if finished { return .cheer }
        guard isCounting else { return .coach }
        return exercise == .pushUps ? .pushUp(down: counter.depth > 0.5) : .flex
    }

    private var isFloorMovement: Bool { exercise == .pushUps }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // One reserved box for both states. The camera window and Rex are
            // different heights, and this view has springs on it - without a
            // shared box the swap animates the whole column and the preview
            // appears to lurch.
            ZStack {
                if cameraIsLive && !finished {
                    CameraWindow(
                        session: counter.previewSession,
                        exercise: exercise,
                        pose: counter.poseFrame,
                        reps: reps,
                        target: target,
                        status: cameraStatus
                    )
                    // The same status light the set screen uses. The detector is
                    // identical here, so the feedback has to be too: a rep refused
                    // in the intake with no visible reason is the first impression
                    // of a counter that looks broken.
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(borderColour ?? .clear,
                                          lineWidth: borderColour == nil ? 0 : 4)
                    )
                    .animation(.easeInOut(duration: 0.2), value: borderColour)
                } else {
                    RexImage(pose: pose, size: 150)
                }
            }
            // Sized like the set screen rather than the postage stamp this used
            // to be. Doing a push-up means looking at the phone from a foot away
            // at a bad angle, and a 240pt window put the skeleton and the count
            // too small to read from the floor. The aspect ratio holds the box's
            // shape; the max height keeps it off the copy on a small phone.
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 460)

            Group {
                if !isCounting && !finished {
                    intro
                } else if finished {
                    payoff
                } else {
                    counterReadout
                }
            }
            // With the camera up the count lives on the video, so this block is
            // only the form hint and does not need the taller slot.
            // Taller before the set starts: the intro now carries the movement
            // picker under its two lines, and at 132 the subtitle was truncating
            // mid-sentence to make room for it.
            .frame(height: cameraIsLive && !finished ? 76 : 210, alignment: .top)

            Spacer()

            footer
        }
        .padding(.horizontal, Metrics.screenPadding)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCounting)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: finished)
        .animation(.easeInOut(duration: 0.25), value: cameraIsLive)
        .onDisappear { counter.cancel() }
        .onChange(of: counter.reps) { _, count in
            guard count >= target, !finished else { return }
            finished = true
            counter.stop()
            Haptics.celebrate()
        }
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Text("Let's try \(target) \(exercise.title.lowercased()).")
                .font(RansomFont.title(28))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text("Nothing to unlock yet. Just a warm-up, so you can feel how it works.")
                .font(RansomFont.body(16))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            movementPicker
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    /// Push-ups or squats, chosen here rather than only two screens back.
    ///
    /// Swapping rebuilds the counter, which is the whole reason this cannot just
    /// set a variable: the detector is built for one movement - which joints it
    /// reads and what counts as a rep differ completely - so a counter made for
    /// push-ups would simply never see a squat.
    private var movementPicker: some View {
        HStack(spacing: 8) {
            ForEach(Exercise.selectable) { option in
                Button {
                    guard option != exercise else { return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        exercise = option
                    }
                    counter = PoseRepCounter(exercise: option, target: Self.target)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(option.shortTitle)
                            .font(RansomFont.headline(15))
                    }
                    .foregroundStyle(option == exercise ? Palette.onBrand : Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(option == exercise ? Palette.brand : Palette.surfaceAlt)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    private var counterReadout: some View {
        VStack(spacing: 6) {
            // With the camera up the count is drawn on the video itself; without
            // it there's no self-view to put it on, so it goes here.
            if !cameraIsLive {
                Text("\(reps)")
                    .font(RansomFont.counter(84))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(reps)))
                    .animation(.snappy(duration: 0.2), value: reps)
                Text("of \(target)")
                    .font(RansomFont.headline(18))
                    .foregroundStyle(Palette.inkSoft)
            }
            // Read from the floor mid-push-up, so a correction gets size and
            // colour rather than being the quietest thing on the screen.
            Text(hintText)
                .font(hasFeedback ? RansomFont.title(20) : RansomFont.body(14))
                .foregroundStyle(hasFeedback ? Palette.danger : Palette.inkFaint)
                .multilineTextAlignment(.center)
                .frame(height: 52)
                .padding(.horizontal, 12)
                .animation(.easeInOut(duration: 0.15), value: hintText)
        }
        .padding(.top, 8)
    }

    /// Form correction first, then the setup instruction for whichever counter is
    /// actually running. The sensor cue tells you to put the phone under your
    /// chest, which is the wrong advice entirely when the camera is watching.
    /// True while there is something to say about the last rep.
    private var hasFeedback: Bool { cameraIsLive && counter.formHint != nil }

    /// Green while it is counting cleanly, red the moment a rep is refused,
    /// nothing while it is still looking for you.
    private var borderColour: Color? {
        guard cameraIsLive else { return nil }
        if hasFeedback { return Palette.danger }
        return counter.tracking == .tracking ? Palette.green : nil
    }

    private var cameraStatus: String? {
        switch counter.tracking {
        case .searching:   return "Looking for you…"
        case .calibrating: return isFloorMovement ? "Hold still at the top to start" : "Stand tall and still to start"
        default:           return nil
        }
    }

    private var hintText: String {
        if let hint = counter.formHint { return hint }
        if case let .blocked(reason) = counter.tracking { return reason }
        return counter.isBlocked ? exercise.coachingCue : exercise.cameraCue
    }

    private var payoff: some View {
        VStack(spacing: 10) {
            Text("First set done!")
                .font(RansomFont.title(28))
                .foregroundStyle(Palette.ink)
            Text("Nice work. Month one is about \(plan.firstMonthReps.formatted()) more, \(plan.repsPerUnlock) at a time. You just did the hardest ones.")
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
                // Nothing to press: the camera is the counter. The skip stays,
                // so a camera that can't see you never traps anyone in intake.
                TextButton(title: "Skip for now") { onNext() }
            } else {
                PrimaryButton(title: isFloorMovement ? "I'm on the floor" : "I'm up, let's go") {
                    isCounting = true
                    Haptics.tap()
                    Task { await counter.start() }
                }
                // No scolding on the way past. The floor is still there later.
                TextButton(title: "Maybe later") { onNext() }
            }
        }
        .padding(.bottom, 28)
    }
}
