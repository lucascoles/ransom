import SwiftUI

/// The set. Full screen, no chrome, one job: count reps and make it feel good.
struct WorkoutView: View {
    var exercise: Exercise
    var target: Int
    /// The app the user was trying to open, when this came from a shield tap.
    var trigger: String?

    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(\.dismiss) private var dismiss

    @State private var engine: RepEngine
    @State private var countdown: Int? = 3
    @State private var showCompletion = false
    @State private var grantedMinutes = 0

    init(exercise: Exercise, target: Int, trigger: String? = nil) {
        self.exercise = exercise
        self.target = target
        self.trigger = trigger
        _engine = State(initialValue: RepEngine(exercise: exercise, target: target))
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            if showCompletion {
                WorkoutCompleteView(
                    exercise: exercise,
                    reps: engine.reps,
                    minutes: grantedMinutes,
                    trigger: trigger,
                    onDone: { dismiss() }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                counting
            }

            if let countdown {
                CountdownOverlay(value: countdown)
            }
        }
        .statusBarHidden(!showCompletion)
        .onAppear(perform: runCountdown)
        .onChange(of: engine.phase) { _, phase in
            if phase == .finished { finish() }
        }
    }

    // MARK: - Counting

    private var counting: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            ZStack {
                ProgressRing(progress: engine.progress, lineWidth: 14)
                    .frame(width: 300, height: 300)

                VStack(spacing: -6) {
                    Text("\(engine.reps)")
                        .font(ReppFont.counter(110))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(engine.reps)))
                        .animation(.snappy(duration: 0.2), value: engine.reps)
                    Text("of \(target)")
                        .font(ReppFont.headline(19))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.bottom, 4)

            RexImage(pose: .pushUp(down: engine.depth > 0.5), size: 168, depth: engine.depth)
                .padding(.top, -8)

            Text(engine.formHint ?? exercise.coachingCue)
                .font(ReppFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(height: 40)
                .padding(.horizontal, 40)
                .animation(.easeInOut, value: engine.formHint)

            Spacer(minLength: 0)

            footer
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere is always a valid rep — sensors assist, they don't gate.
            engine.registerManualRep()
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.tap()
                engine.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Palette.surfaceAlt))
            }
            .pressable(scale: 0.9)

            Spacer()

            Pill(
                text: exercise.title,
                icon: exercise.symbol,
                tint: Palette.ink,
                background: Palette.surfaceAlt
            )

            Spacer()

            // Balances the close button so the pill stays centred.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Tap the screen if a rep doesn't register")
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkFaint)

            SecondaryButton(title: "Stop the set", icon: "stop.fill") {
                engine.stop()
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Flow

    private func runCountdown() {
        for step in 0...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.8) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if step < 3 {
                        countdown = 3 - step
                        Haptics.tap()
                    } else {
                        countdown = nil
                        Haptics.select()
                        engine.start()
                    }
                }
            }
        }
    }

    private func finish() {
        guard !showCompletion else { return }
        // A stopped-early set still counts — partial credit beats a rage quit,
        // but no time is granted unless the target was met.
        let earnedFullSet = engine.reps >= target

        if earnedFullSet {
            grantedMinutes = model.completeSet(
                exercise: exercise,
                reps: engine.reps,
                duration: engine.elapsedSeconds,
                trigger: trigger
            )
            screenTime.grantEarnedTime(minutes: grantedMinutes)
            Haptics.celebrate()
        } else if engine.reps > 0 {
            model.history.append(
                WorkoutRecord(
                    exercise: exercise,
                    reps: engine.reps,
                    durationSeconds: engine.elapsedSeconds,
                    minutesGranted: 0,
                    trigger: trigger
                )
            )
            grantedMinutes = 0
            Haptics.warning()
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showCompletion = true
        }
    }
}

/// The 3–2–1 that gets you into position.
private struct CountdownOverlay: View {
    var value: Int

    var body: some View {
        ZStack {
            Palette.canvas.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                RexImage(pose: .coach, size: 150)
                Text("\(value)")
                    .font(ReppFont.counter(96))
                    .foregroundStyle(Palette.green)
                    .id(value)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Text("Get into position")
                    .font(ReppFont.headline(17))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .transition(.opacity)
    }
}
