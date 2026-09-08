import SwiftUI

// MARK: - Projection

/// The number that changes the room.
///
/// Every figure here is computed from the hours the user gave two screens ago —
/// nothing is invented, and the footnote states the two assumptions out loud so
/// the arithmetic can be checked rather than merely believed. A projection that
/// can be caught exaggerating buys nothing and costs the rest of the funnel.
struct ProjectionStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    /// How much of the argument has landed. Each stage is one thought.
    ///
    /// The whole thing used to arrive in two lumps, stacked in the top half of a
    /// screen that was two thirds empty. A number this size needs the room and the
    /// pause: read the year first, feel it, then be told what it adds up to. Given
    /// all at once it is a paragraph, and a paragraph gets skimmed.
    @State private var stage = 0
    /// Set by a tap, which finishes whatever is typing rather than jumping past
    /// a line the reader has not seen.
    @State private var hasSkipped = false

    private let stages = 3

    private var minutesPerDay: Int { profile.baselineDailyMinutes }
    private var daysPerYear: Double { Double(minutesPerDay) * 365 / (60 * 24) }

    /// Waking years, not calendar years. Sixteen waking hours a day is the honest
    /// denominator: nobody scrolls in their sleep, and dividing by twenty-four
    /// would quietly shrink the number in the app's own favour.
    private var wakingYearsLeft: Double {
        let yearsRemaining = max(0, 85 - Double(profile.age))
        return yearsRemaining * (Double(minutesPerDay) / (16 * 60))
    }

    var body: some View {
        StepScaffold(
            title: "",
            buttonTitle: "I don't love that",
            showsButton: stage >= stages - 1,
            onNext: onNext
        ) {
            // Spread down the whole height rather than piling into the top. The
            // spacers are weighted so the big number sits slightly above centre,
            // where the eye lands first.
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 8)

                TypedStack(
                    lines: [
                        .line("At your current rate, you'll spend", RansomFont.body(17), Palette.inkSoft),
                        .line("\(Int(daysPerYear.rounded())) days", RansomFont.counter(58), Palette.ink),
                        .line("on your phone over the next year.", RansomFont.title(22), Palette.ink),
                    ],
                    alignment: .leading,
                    perCharacter: 0.03,
                    isInstant: hasSkipped,
                    onComplete: { advance() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 20)

                if stage >= 1 {
                    TypedStack(
                        lines: [
                            .line("Which puts you on track for", RansomFont.body(17), Palette.inkSoft, leadIn: 0.5),
                            .line("\(String(format: "%.1f", wakingYearsLeft)) years", RansomFont.counter(76), Palette.danger,
                                  leadIn: 0.35, fitsOneLine: true),
                            .line("of the time you're awake, spent looking down.", RansomFont.title(22), Palette.ink),
                        ],
                        alignment: .leading,
                        perCharacter: 0.03,
                        isInstant: hasSkipped,
                        onComplete: { advance() }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

                Spacer(minLength: 20)

                Text("Based on the \(minutesPerDay) minutes a day you just told us, an 85-year life, and 16 waking hours a day.")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(stage >= 2 ? 1 : 0)

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The scaffold puts its content in a ScrollView, which offers
            // unbounded height, so spacers inside it collapse to nothing and
            // everything piles into the top. Matching the scroll container's own
            // height gives them something to divide.
            .containerRelativeFrame(.vertical)
            .contentShape(Rectangle())
            // Impatience should skip ahead, never be ignored.
            .onTapGesture { hasSkipped = true }
        }
    }

    /// Called when a typed block finishes, so the pacing follows the words
    /// rather than a timer that has to be kept in step with them.
    private func advance() {
        guard stage < stages - 1 else { return }
        // The years figure is the sting, so that is where the haptic lands.
        if stage == 0 { Haptics.warning() }
        withAnimation(.easeOut(duration: 0.25)) { stage += 1 }
    }
}

// MARK: - Commitment

/// Locking the plan in for a fixed run.
///
/// The whole mechanism fails the moment it can be softened from inside a craving:
/// somebody who can drop to the easiest setting at the exact instant they don't
/// fancy it has an app that agrees with them every time. Committing up front, in
/// a calm moment, is the user setting terms for a version of themselves who will
/// be arguing in bad faith later.
struct CommitmentStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    private var exercise: Exercise { profile.primaryExercise }

    /// Whether the custom row owns the current value. Tracked separately because a
    /// custom run can land on a preset's number, and without this both rows would
    /// light up at fourteen days.
    @State private var isCustom = false
    @State private var customDays = CommitmentStep.minimumDays

    /// Five days is the floor. Below that it isn't a commitment, it's a weekend —
    /// too short to survive a single bad evening, which is the exact thing the
    /// commitment exists to survive.
    static let minimumDays = 5
    static let maximumDays = 90

    var body: some View {
        StepScaffold(
            title: "Lock it in",
            subtitle: "Pick how long you're committing for. You can make it harder whenever you like - just not easier.",
            isButtonEnabled: profile.commitmentDays != nil,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(CommitmentLength.allCases) { length in
                    ChoiceCard(
                        title: length.title,
                        subtitle: length.subtitle,
                        icon: "lock.fill",
                        isSelected: !isCustom && profile.commitmentDays == length.days
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCustom = false
                            commit(days: length.days)
                        }
                    }
                }

                ChoiceCard(
                    title: "Custom",
                    subtitle: isCustom ? "Your own run." : "Pick your own number of days.",
                    icon: "slider.horizontal.3",
                    isSelected: isCustom
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCustom = true
                        commit(days: customDays)
                    }
                }

                if isCustom {
                    VStack(spacing: 12) {
                        Text("\(customDays) day\(customDays == 1 ? "" : "s")")
                            .font(RansomFont.counter(38))
                            .foregroundStyle(Palette.brand)
                            .contentTransition(.numericText(value: Double(customDays)))

                        Slider(
                            value: Binding(
                                get: { Double(customDays) },
                                set: {
                                    let days = Int($0.rounded())
                                    // Only on a real step change, or a single drag
                                    // fires a tap per frame.
                                    if days != customDays { Haptics.tick() }
                                    customDays = days
                                    commit(days: days)
                                }
                            ),
                            in: Double(Self.minimumDays)...Double(Self.maximumDays),
                            step: 1
                        )
                        .tint(Palette.brand)

                        HStack {
                            Text("\(Self.minimumDays) days minimum")
                            Spacer()
                            Text("\(Self.maximumDays)")
                        }
                        .font(RansomFont.caption(11))
                        .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(Palette.surfaceAlt)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let days = profile.commitmentDays {
                    Text("For the next \(days) days you'll earn minutes by doing \(exercise.title.lowercased()). Rex will hold you to it.")
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isCustom)
        }
    }

    /// One place that writes the commitment, so the start date can never be set
    /// on one path and forgotten on another.
    private func commit(days: Int) {
        profile.commitmentDays = max(Self.minimumDays, days)
        profile.commitmentStartedAt = Date()
    }
}

/// The runs on offer. Five days is the one almost nobody refuses, which is why
/// it leads — a commitment declined is worth nothing at all.
enum CommitmentLength: Int, CaseIterable, Identifiable {
    case five = 5
    case fourteen = 14
    case thirty = 30

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// Short form for the inline picker, where three chips share a row.
    var shortTitle: String {
        switch self {
        case .five:     return "5 days"
        case .fourteen: return "2 weeks"
        case .thirty:   return "30 days"
        }
    }

    var title: String {
        switch self {
        case .five:     return "5 days"
        case .fourteen: return "2 weeks"
        case .thirty:   return "30 days"
        }
    }

    var subtitle: String {
        switch self {
        case .five:     return "A proper try. Most people start here."
        case .fourteen: return "Long enough to feel different."
        case .thirty:   return "Long enough to be different."
        }
    }
}

// MARK: - Banked minutes explainer

/// How the economy works, in one screen, before the paywall asks them to buy it.
struct BankExplainerStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @State private var filled = false

    private var plan: RansomPlan { RansomPlan.make(from: profile) }
    private var exercise: Exercise { profile.primaryExercise }

    var body: some View {
        StepScaffold(
            title: "Minutes you don't spend are banked",
            subtitle: "Earn them whenever you like. Spend them whenever you need them.",
            onNext: onNext
        ) {
            VStack(spacing: 22) {
                // A tank rather than a bar: a bar reads as progress toward a goal,
                // and this is a balance that goes down as well as up.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Palette.surfaceAlt)

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Palette.brand)
                        .frame(height: filled ? 150 : 0)

                    VStack(spacing: 2) {
                        Text("\(plan.minutesPerUnlock)")
                            .font(RansomFont.counter(44))
                            .foregroundStyle(.white)
                        Text("minutes banked")
                            .font(RansomFont.caption(12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.bottom, 34)
                    .opacity(filled ? 1 : 0)
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    bullet("\(plan.setTarget) \(exercise.title.lowercased()) fills it by \(plan.minutesPerUnlock) minutes.")
                    // The cap is part of the offer, not fine print. "Walking pays"
                    // without "up to here" is the version that reads as a loophole
                    // and gets found the first evening somebody tests it.
                    //
                    // Only for people who chose walking. Steps are banked from the
                    // Walking tab, which does not exist for anyone else, so this
                    // was a promise made to people it could not be kept for.
                    if profile.exercises.contains(.steps) {
                        bullet("Walking pays too, up to \(plan.stepMinutesCap) minutes a day.")
                    }
                    bullet("Open a blocked app and it spends from the bank.")
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) {
                    filled = true
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.brand)
                .padding(.top, 1)
            Text(text)
                .font(RansomFont.body(15))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
