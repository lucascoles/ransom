import SwiftUI

/// The set. Full screen, no chrome, one job: count reps and make it feel good.
///
/// The camera counts push-ups and squats, because a pose-checked rep is the only
/// kind that can't be faked. Everything else — a refused camera, no camera at
/// all — falls through to the sensor engine, so the user is never stuck.
///
/// There is deliberately **no tap-to-count**. It was there as a safety net, but a
/// button that adds a rep for free undoes the entire point of watching the body:
/// the honest count and the free one sit on the same screen, and the free one
/// always wins.
struct WorkoutView: View {
    var exercise: Exercise
    var target: Int
    /// The app the user was trying to open, when this came from a shield tap.
    var trigger: String?

    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(\.dismiss) private var dismiss

    @State private var pose: PoseRepCounter
    /// Created only once the camera has been ruled out.
    @State private var fallback: RepEngine?
    @State private var countdown: Int? = 3
    @State private var showCompletion = false
    @State private var grantedMinutes = 0

    /// `-RansomDebugHUD 1` shows the detector readout under the camera.
    private var showsDiagnostics: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "RansomDebugHUD")
        #else
        return false
        #endif
    }

    init(exercise: Exercise, target: Int, trigger: String? = nil) {
        self.exercise = exercise
        self.target = target
        self.trigger = trigger
        _pose = State(initialValue: PoseRepCounter(exercise: exercise, target: target))
    }

    // MARK: - Unified counter surface
    //
    // The screen shouldn't care which counter is running. These read from the
    // fallback when it exists and the camera otherwise.

    private var usingCamera: Bool { fallback == nil }
    private var reps: Int { fallback?.reps ?? pose.reps }
    private var depth: Double { fallback?.depth ?? pose.depth }
    private var progress: Double { fallback?.progress ?? pose.progress }
    private var elapsedSeconds: Int { fallback?.elapsedSeconds ?? pose.elapsedSeconds }
    private var formHint: String? { fallback?.formHint ?? pose.formHint }

    /// Whether this set is being counted by the camera at all.
    ///
    /// Deliberately not "is the camera warmed up yet". It used to also require
    /// `tracking != .idle`, which is only true once `AVCaptureSession` has
    /// delivered its first frame - so for the second or so between the countdown
    /// ending and the camera producing anything, the whole no-camera layout was
    /// drawn: ring, counter, a Rex illustration and "prop the phone against a
    /// wall", all of it then thrown away and replaced by the video. It read as a
    /// screen the user had to get past, and it was really just a loading state
    /// wearing the fallback UI's clothes.
    ///
    /// Deciding on intent instead means the camera layout is on screen from the
    /// first frame of the set, with the preview filling in underneath it. The
    /// sensor layout is now only ever shown to somebody who is genuinely not
    /// being watched by a camera.
    private var cameraIsLive: Bool {
        usingCamera && !pose.isBlocked
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            if showCompletion {
                WorkoutCompleteView(
                    exercise: exercise,
                    reps: reps,
                    minutes: grantedMinutes,
                    trigger: trigger,
                    // Same guard as Home: spending is irreversible and an
                    // unlock with no permission or no chosen apps opens nothing,
                    // so the coins stay banked instead.
                    onUseNow: {
                        guard screenTime.canUnlock else {
                            dismiss()
                            return
                        }
                        let spent = model.spendFromBank(minutes: grantedMinutes)
                        if spent > 0 { screenTime.grantEarnedTime(minutes: spent) }
                        dismiss()
                    },
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
                CountdownOverlay(value: countdown, exercise: exercise)
            }
        }
        .statusBarHidden(!showCompletion)
        .animation(.easeInOut(duration: 0.3), value: cameraIsLive)
        .onAppear(perform: runCountdown)
        .onDisappear { pose.cancel() }
        // The camera ruling itself out is what promotes the sensor engine. Doing
        // it here rather than up front means the user is never asked to choose,
        // and never sees a permission prompt they can't act on.
        .onChange(of: pose.isBlocked) { _, blocked in
            if blocked, fallback == nil { startFallback() }
        }
        .onChange(of: pose.phase) { _, phase in
            if phase == .finished { finish() }
        }
        .onChange(of: fallback?.phase) { _, phase in
            if phase == .finished { finish() }
        }
    }

    // MARK: - Counting

    private var counting: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            if cameraIsLive {
                cameraLayout
            } else {
                sensorLayout
            }

            Text(hintText)
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(height: 42)
                .padding(.horizontal, 36)
                .padding(.top, 12)
                .animation(.easeInOut, value: hintText)

            Spacer(minLength: 0)

            footer
        }
    }

    /// The camera layout puts the count on the video, where the user is already
    /// looking, and leaves the progress to a thin bar underneath.
    private var cameraLayout: some View {
        VStack(spacing: 16) {
            // Feedback takes the headline whenever there is any.
            //
            // Read from the floor, mid-push-up, at arm's length and often upside
            // down in the eyeline: small grey text under the video is invisible
            // exactly when it matters. "Go!" is decoration by comparison, and the
            // reason a rep didn't count is the most important thing on the screen
            // the moment it exists.
            //
            // A setup problem is shouted rather than explained, because the
            // explanation is unreadable from where the user is lying. Two words
            // at 40pt carry the instruction; the sentence sits under them for
            // whoever has time to read it.
            VStack(spacing: 4) {
                Text(banner.text)
                    .font(RansomFont.title(banner.shouts ? 46 : 28))
                    .foregroundStyle(banner.tint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)

                if let detail = banner.detail {
                    Text(detail)
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .frame(minHeight: 88)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: banner.text)

            CameraWindow(
                session: pose.previewSession,
                exercise: exercise,
                pose: pose.poseFrame,
                reps: reps,
                target: target,
                status: cameraStatus,
                isLive: pose.tracking == .tracking
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(borderColour ?? .clear, lineWidth: borderColour == nil ? 0 : 4)
            )
            .animation(.easeInOut(duration: 0.2), value: borderColour)
            .padding(.horizontal, Metrics.screenPadding)

            StepProgressBar(progress: progress)
                .padding(.horizontal, Metrics.screenPadding + 6)

            #if DEBUG
            // What the detector is actually seeing. Off by default - it's noise
            // under the camera for anyone not debugging - but one launch flag
            // away, because tuning rep detection without it is guesswork, and
            // reading these numbers off a screen recording is how the counter got
            // fixed. Never ships either way.
            if showsDiagnostics, let diagnostics = pose.diagnostics {
                Text(diagnostics)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.inkFaint)
            }
            #endif
        }
    }

    /// No camera: the original ring, counter and Rex.
    private var sensorLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 14)
                    .frame(width: 300, height: 300)

                VStack(spacing: -6) {
                    Text("\(reps)")
                        .font(RansomFont.counter(110))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(reps)))
                        .animation(.snappy(duration: 0.2), value: reps)
                    Text("of \(target)")
                        .font(RansomFont.headline(19))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .padding(.bottom, 4)

            // The push-up frames share the standing poses' portrait canvas, so
            // Rex lies in the bottom third of it and the top is empty. Pulling
            // him up closes what otherwise reads as a hole under the ring.
            RexImage(pose: .pushUp(down: depth > 0.5), size: 168, depth: depth)
                .padding(.top, -72)
        }
    }

    /// Only the states the user can act on. "Tracking" needs no label — the
    /// skeleton on their body already says it.
    /// Only the states the banner above the window isn't already shouting.
    ///
    /// "Looking for you" and the arming cue both moved up there, where they are
    /// legible; repeating them inside the frame in 12pt was the same sentence
    /// twice in two sizes.
    private var cameraStatus: String? {
        // The window is on screen before the session has delivered anything, so
        // this covers the brief black frame rather than leaving it unexplained.
        pose.tracking == .idle ? "Getting the camera ready…" : nil
    }

    /// True while there is something to say about the last rep.
    private var hasFeedback: Bool { usingCamera && formHint != nil }

    /// The frame's own status light: green while it is counting cleanly, red the
    /// moment a rep is refused, nothing while it is still looking for you.
    ///
    /// The green matters as much as the red. Without it the border only ever
    /// appears to deliver bad news, so its absence has to carry "everything is
    /// fine" - and absence is not something anyone reads mid-rep. A colour that
    /// is always saying something is legible at a glance from the floor.
    private var borderColour: Color? {
        guard usingCamera else { return nil }
        if hasFeedback || pose.blocker != nil { return Palette.danger }
        return pose.tracking == .tracking ? Palette.green : nil
    }

    /// What the screen says, how loudly, and in what colour.
    ///
    /// Four things can be true at once, and they are ordered by what the user
    /// can do about them: a setup problem stops every rep and is fixed by
    /// moving, a refused rep is fixed by going deeper, and the rest is just
    /// telling them whether the count is live.
    ///
    /// "GET SET" is shouted at the same size as a problem, because people were
    /// starting their set into a counter that had not armed yet and losing the
    /// first few reps. At 26pt in the same grey as everything else, it read as a
    /// label rather than an instruction to wait.
    private var banner: (text: String, detail: String?, tint: Color, shouts: Bool) {
        guard usingCamera else {
            return (formHint ?? "Go!", nil, formHint == nil ? Palette.ink : Palette.danger, false)
        }
        if let blocker = pose.blocker {
            return (blocker.shout, formHint ?? blocker.detail, Palette.danger, true)
        }
        if let formHint { return (formHint, nil, Palette.danger, false) }
        if pose.tracking == .tracking { return ("GO!", nil, Palette.green, true) }
        return ("GET SET", exercise.armingCue, Palette.brand, true)
    }

    /// Form correction first, then whatever the user most needs to hear: how to
    /// set the phone up, or the movement cue for the sensor path.
    private var hintText: String {
        // Deliberately not the form hint: that has the headline now, and printing
        // it twice on one screen reads as a stutter.
        guard usingCamera else { return formHint ?? exercise.coachingCue }
        if case let .blocked(reason) = pose.tracking { return reason }
        // The banner is already carrying a sentence. Printing the setup cue
        // under it as well gives two instructions at once, which is how someone
        // mid-set ends up reading neither.
        return banner.detail == nil ? exercise.cameraCue : ""
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.tap()
                pose.cancel()
                fallback?.cancel()
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
            Text(footerNote)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metrics.screenPadding)

            SecondaryButton(title: "Stop here", icon: "stop.fill") {
                if let fallback { fallback.stop() } else { pose.stop() }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .padding(.bottom, 24)
    }

    /// Says what's counting. Users forgive a missed rep; they don't forgive not
    /// knowing whether the thing is even watching.
    private var footerNote: String {
        guard usingCamera else { return "Counting with the phone's sensors" }
        return pose.tracking == .tracking ? "Rex is counting. Nothing is recorded." : "Nothing is recorded or uploaded"
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
                        Task { await pose.start() }
                    }
                }
            }
        }
    }

    /// Promotes the sensor engine when the camera can't run.
    private func startFallback() {
        let engine = RepEngine(exercise: exercise, target: target)
        fallback = engine
        engine.start()
    }

    private func finish() {
        guard !showCompletion else { return }
        // A stopped-early set still counts — partial credit beats a rage quit,
        // but no time is granted unless the target was met.
        let earnedFullSet = reps >= target

        if earnedFullSet {
            grantedMinutes = model.completeSet(
                exercise: exercise,
                reps: reps,
                duration: elapsedSeconds,
                trigger: trigger
            )
            // Banked, not spent. Granting here was what made finishing a set open
            // the apps whether or not that was wanted, and turned every set into a
            // countdown the user hadn't asked to start.
            Haptics.celebrate()
        } else if reps > 0 {
            model.history.append(
                WorkoutRecord(
                    exercise: exercise,
                    reps: reps,
                    durationSeconds: elapsedSeconds,
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
    var exercise: Exercise

    var body: some View {
        ZStack {
            Palette.canvas.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                RexImage(pose: .coach, size: 150)
                Text("\(value)")
                    .font(RansomFont.counter(96))
                    .foregroundStyle(Palette.brand)
                    .id(value)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                // The setup instruction belongs here, before the set starts —
                // once you're mid-push-up it's too late to move the phone.
                Text(exercise.cameraCue)
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
        }
        .transition(.opacity)
    }
}
