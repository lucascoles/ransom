import SwiftUI

// MARK: - Which apps

/// Quick picks only. Naming the habit, not configuring it.
///
/// The grid is deliberately emoji, not logos. Apple only renders a real app icon
/// through `Label(ApplicationToken)`, and a token only exists for apps the user has
/// already chosen in `FamilyActivityPicker` — so an icon shown *before* selection
/// would have to be our own copy of someone else's trademark.
///
/// There is deliberately no "Other" tile handing off to the system picker. That
/// picker needs Family Controls authorization, which isn't granted this early, so
/// the tile read as dead on tap — and the exact-app choice already has a home on
/// the main screen, which is where the subtitle sends them.
struct AppsStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    @Environment(ScreenTimeManager.self) private var screenTime

    @State private var picksOther = false

    /// Counted off `screenTime.selection` rather than the store, because only the
    /// mirrored selection is observable: reading the store would leave this tile
    /// unchecked after the picker closes.
    private var systemPickedCount: Int {
        let selection = screenTime.selection
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var body: some View {
        StepScaffold(
            title: "Which apps pull you in?",
            subtitle: "Tap all that apply. You'll pick the exact apps later.",
            isButtonEnabled: !profile.distractingApps.isEmpty || picksOther || systemPickedCount > 0,
            footnote: "Nothing gets deleted. Your apps just get a quick warm-up first.",
            onNext: onNext
        ) {
            VStack(spacing: 10) {
                ForEach(DistractingApp.allCases) { app in
                    AppRow(
                        emoji: app.emoji,
                        title: app.title,
                        isSelected: profile.distractingApps.contains(app)
                    ) {
                        toggle(app)
                    }
                }

                // Deliberately inert. It exists so nobody scans the list, fails to
                // find their app and assumes this isn't for them — the real choice
                // of apps happens later, in Apple's own picker, where every app on
                // the phone is available.
                AppRow(
                    emoji: "➕",
                    title: "Something else",
                    isSelected: picksOther
                ) {
                    Haptics.select()
                    picksOther.toggle()
                }
            }

            if systemPickedCount > 0 {
                Text("\(systemPickedCount) more picked from your phone.")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
        }
    }

    private func toggle(_ app: DistractingApp) {
        Haptics.select()
        if profile.distractingApps.contains(app) {
            profile.distractingApps.remove(app)
        } else {
            profile.distractingApps.insert(app)
        }
    }
}

/// A full-width row rather than a tile in a grid.
///
/// Two-up tiles turn a list of familiar names into a puzzle to be scanned; one
/// per row reads top to bottom the way a list is meant to, gives every name the
/// same weight, and leaves room for the name to sit beside its icon instead of
/// under it.
private struct AppRow: View {
    var emoji: String
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.surfaceAlt))

                Text(title)
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.ink)

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Palette.hairline, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    if isSelected {
                        Circle().fill(Palette.brand).frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.brandSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.brand : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .pressable(scale: 0.98)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - How much

struct ScrollLoadStep: View {
    @Binding var profile: UserProfile
    /// Three-state on purpose: an unanswered bedtime question and a "no" both leave
    /// `peakTimes` empty, and the Continue button has to tell them apart. Owned by
    /// the flow so back-navigation doesn't lose a "no".
    @Binding var scrollsInBed: Bool?
    var onNext: () -> Void

    private var hasAnswer: Bool { (profile.measuredDailyMinutes ?? 0) > 0 }

    /// Four hours. Well above the "I probably use it a bit much" figure people
    /// reach for unprompted, and close to what phones actually report — starting
    /// here means the projection two screens later is built on something real
    /// rather than on a number chosen to feel comfortable.
    private static let defaultMinutes = 240
    private static let minimumMinutes = 60
    private static let maximumMinutes = 720

    private var minutes: Int { profile.measuredDailyMinutes ?? Self.defaultMinutes }

    var body: some View {
        StepScaffold(
            title: "How much time do they get?",
            subtitle: "A rough guess is fine. Most people land higher than they expect.",
            isButtonEnabled: hasAnswer && scrollsInBed != nil,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                estimateSlider

                // Load-bearing, not decoration. This answer is the only switch for
                // the late-night surcharge (AppModel reads `peakTimes.contains(.lateNight)`),
                // so it gets asked as a real question with the price attached.
                if hasAnswer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Do you scroll in bed?")
                            .font(RansomFont.title(22))
                            .foregroundStyle(Palette.ink)
                            .padding(.top, 14)

                        Text(bedtimePrice)
                            .font(RansomFont.body(14))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)

                        ChoiceCard(
                            title: "Yes, most nights",
                            emoji: "🌙",
                            isSelected: scrollsInBed == true
                        ) {
                            setBedtime(true)
                        }

                        ChoiceCard(
                            title: "No, phone's down by then",
                            emoji: "😴",
                            isSelected: scrollsInBed == false
                        ) {
                            setBedtime(false)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onAppear {
                // Commit the default on arrival rather than waiting for a drag.
                //
                // The slider showed four hours from the first frame but nothing
                // was written until it moved, so the bedtime question below stayed
                // hidden and Continue stayed dead for anyone whose honest answer
                // was already on screen. Four hours is a real answer, not a
                // placeholder, so it is recorded as one.
                if profile.measuredDailyMinutes == nil {
                    setMinutes(Self.defaultMinutes)
                }
                if scrollsInBed == nil && profile.peakTimes.contains(.lateNight) {
                    scrollsInBed = true
                }
            }
        }
    }

    /// The bedtime answer no longer sets a price - the tariff is gone - but it
    /// still shapes what Rex says and when he says it, so the question earns its
    /// place on the screen.
    private var estimateSlider: some View {
        VStack(spacing: 16) {
            Text(label(for: minutes))
                .font(RansomFont.counter(52))
                .foregroundStyle(Palette.brand)
                .contentTransition(.numericText(value: Double(minutes)))

            Slider(
                value: Binding(
                    get: { Double(minutes) },
                    set: { newValue in
                        let stepped = Int((newValue / 15).rounded()) * 15
                        if stepped != profile.measuredDailyMinutes { Haptics.tick() }
                        setMinutes(stepped)
                    }
                ),
                in: Double(Self.minimumMinutes)...Double(Self.maximumMinutes),
                step: 15
            )
            .tint(Palette.brand)

            HStack {
                Text("1h")
                Spacer()
                Text("12h+")
            }
            .font(RansomFont.caption(11))
            .foregroundStyle(Palette.inkFaint)

        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private func label(for minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let text = hours == 0 ? "\(rest)m" : (rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m")
        return minutes >= Self.maximumMinutes ? text + "+" : text
    }

    /// Writes the exact figure and keeps the coarse bucket in step with it, since
    /// the tariff and a few older screens still read the bucket.
    private func setMinutes(_ value: Int) {
        let clamped = min(max(value, Self.minimumMinutes), Self.maximumMinutes)
        profile.measuredDailyMinutes = clamped
        profile.scrollLoad = ScrollLoad.matching(minutes: clamped)
    }

    private func formatted(minutes: Int) -> String {
        guard minutes > 0 else { return "-" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private var bedtimePrice: String {
        "Late-night scrolling is the habit most people want gone first, so Rex keeps a closer eye on the hours before bed."
    }

    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display)\(suffix)"
    }

    private func setBedtime(_ value: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scrollsInBed = value
            if value {
                profile.peakTimes.insert(.lateNight)
            } else {
                profile.peakTimes.remove(.lateNight)
            }
        }
    }
}

// MARK: - The reality check

/// A single hard number, delivered by Rex. This is the emotional turn of the flow —
/// everything before it is data collection, everything after it is the fix.
struct RealityCheckStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @State private var revealed = false

    // Off the exact figure they just set, never the bucket. The bucket rounds a
    // seven-hour habit down to "4+ hours" and prices it at five, so the number on
    // this screen contradicted the number on the one before it.
    private var minutesPerDay: Int { profile.baselineDailyMinutes }
    private var daysPerYear: Int { max(1, Int((Double(minutesPerDay) * 365 / (60 * 24)).rounded())) }
    private var hoursPerYear: Int { Int((Double(minutesPerDay) * 365 / 60).rounded()) }

    private var dailyLabel: String {
        let hours = minutesPerDay / 60
        let rest = minutesPerDay % 60
        if hours == 0 { return "\(rest) minutes" }
        return rest == 0 ? "\(hours) hours" : "\(hours)h \(rest)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexImage(pose: revealed ? .coach : .sad, size: 150)

            VStack(spacing: 6) {
                Text("At \(dailyLabel) a day, that's")
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountingNumber(value: revealed ? daysPerYear : 0, font: RansomFont.display(78), color: Palette.brand)
                    Text("days")
                        .font(RansomFont.title(28))
                        .foregroundStyle(Palette.brand)
                }

                Text("of your year. About \(hoursPerYear.formatted()) hours.")
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.top, 6)
            .multilineTextAlignment(.center)

            // The number lands hard on its own. The turn from "here's the cost" to
            // "here's the fix" has to happen on this screen, or the goal step that
            // follows reads as a punishment for what they just admitted.
            VStack(alignment: .leading, spacing: 12) {
                Text("THE GOOD NEWS")
                    .font(RansomFont.caption(11))
                    .tracking(1.4)
                    .foregroundStyle(Palette.brand)
                    .padding(.bottom, 2)

                bullet("Your apps stay.", detail: "Nothing gets deleted or locked away for good.")
                bullet("A quick set opens them.", detail: "Push-ups, squats, or just walking. You choose, Rex counts.")
                bullet("You still get your scroll.", detail: "You're just a little stronger every time.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 28)
            .padding(.horizontal, Metrics.screenPadding)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)

            Spacer()

            PrimaryButton(title: "Show me how it works", action: onNext)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.25)) {
                revealed = true
            }
        }
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Palette.brand)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RansomFont.headline(15)).foregroundStyle(Palette.ink)
                Text(detail).font(RansomFont.body(14)).foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

// MARK: - Screen time goal

/// The number the whole app is aiming at.
///
/// Placed straight after the reality check, while the cost of the current habit is
/// still on screen: the goal is the answer to what they just read, not an abstract
/// setting. It's theirs to pick — a target the app assigns is a target the app is
/// blamed for, and the one thing worse than missing a goal is missing someone
/// else's.
struct ScreenGoalStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    /// Set on appear from the baseline, so the slider opens somewhere sensible
    /// rather than at zero.
    private var goal: Int { profile.goalDailyMinutes ?? profile.suggestedGoalMinutes }

    private var baseline: Int { profile.baselineDailyMinutes }
    private var saving: Int { max(0, baseline - goal) }

    var body: some View {
        StepScaffold(
            title: "Where do you want to land?",
            subtitle: "Your daily limit for those apps. Rex helps you get there.",
            isButtonEnabled: profile.goalDailyMinutes != nil,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatted(minutes: goal))
                        .font(RansomFont.counter(52))
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText(value: Double(goal)))
                        .animation(.snappy(duration: 0.2), value: goal)
                    Text("a day in the apps you picked")
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                }

                Slider(
                    value: Binding(
                        get: { Double(goal) },
                        set: {
                            let minutes = Int(($0 / 5).rounded()) * 5
                            if minutes != profile.goalDailyMinutes { Haptics.tick() }
                            profile.goalDailyMinutes = minutes
                        }
                    ),
                    in: 5...Double(max(60, baseline)),
                    step: 5
                )
                .tint(Palette.brand)

                // The comparison is the point. A goal shown on its own is a number;
                // shown against what they just admitted to, it's a decision.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Right now: \(formatted(minutes: baseline)) a day.")
                        .font(RansomFont.body(15))
                        .foregroundStyle(Palette.ink)
                    Text(saving > 0
                         ? "That's \(formatted(minutes: saving)) back every day. \(hoursPerWeek) hours a week, yours again."
                         : "Drag it below \(formatted(minutes: baseline)) to win some time back.")
                        .font(RansomFont.body(14))
                        .foregroundStyle(saving > 0 ? Palette.inkSoft : Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Palette.surfaceAlt)
                )
            }
        }
        .onAppear {
            // Committing the suggestion on arrival is what enables Continue: the
            // default is a real answer, and dragging is how you disagree with it.
            if profile.goalDailyMinutes == nil {
                profile.goalDailyMinutes = profile.suggestedGoalMinutes
            }
        }
    }

    private var hoursPerWeek: String {
        String(format: "%.1f", Double(saving) * 7 / 60)
    }

    private func formatted(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
