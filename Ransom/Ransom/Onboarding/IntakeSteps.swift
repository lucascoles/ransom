import SwiftUI

// MARK: - Name

/// The first question, straight after the cold open.
///
/// The welcome screen that used to sit between them was a second front door:
/// the cold open had already introduced Rex, made the joke that is the product
/// thesis, and ended on "tap to begin". A second screen with a second start
/// button and a third statement of the idea was a screen between the reader and
/// the first thing they get to say.
struct NameStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        profile.firstName.trimmingCharacters(in: .whitespaces)
    }

    /// Trimmed on the way out, not only for display. Predictive text puts a
    /// space after every accepted word, so "Sam " reached the plan title as
    /// "Sam , your plan is ready" and Rex's lines as "minutes, Sam .".
    private func finish() {
        profile.firstName = trimmedName
        onNext()
    }

    var body: some View {
        StepScaffold(
            title: "What should Rex call you?",
            subtitle: "Optional. Rex just likes cheering people on by name.",
            buttonTitle: "Continue",
            onNext: finish
        ) {
            VStack(spacing: 18) {
                TextField("First name", text: $profile.firstName)
                    .font(RansomFont.title(22))
                    .foregroundStyle(Palette.ink)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(finish)
                    .padding(.vertical, 6)
                    .ransomCard()

                // Two scenes in a fixed slot rather than one with a swapped pose:
                // the wave and the cheer are different views, and letting the
                // swap resize the row would nudge the text field mid-typing.
                ZStack(alignment: .topLeading) {
                    if trimmedName.isEmpty {
                        IntakeRexScene(
                            pose: .wave,
                            line: "Hi there! No name is fine too. I'll cheer either way.",
                            size: 96
                        )
                        .transition(.opacity)
                    } else {
                        RexScene(
                            pose: .cheer,
                            line: "\(trimmedName)! Great to have you here.",
                            size: 96
                        )
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: trimmedName.isEmpty)
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Weight

/// One picker, for the one body figure anything reads.
///
/// This replaced a two-wheel height-and-weight screen. Height was collected and
/// never read by a single line in the app, which is personal data asked for
/// under a promise the code did not keep. Weight earns its place: the calorie
/// figures on the stats screen are quoted at a reference bodyweight and scaled
/// from there, so without this every user gets the estimate for a 72 kg adult.
///
/// The subtitle used to offer a skip. There is no skip button: `StepScaffold`
/// gives this screen a Continue and nothing else, and the wheel always holds a
/// value, so everybody answers whether they meant to or not. Offering an exit
/// that does not exist is worse than not offering one.
///
/// `WorkoutRecord.calories(forWeightKg:)` still falls back to the reference
/// weight rather than to zero, which is what keeps profiles made before this
/// screen existed reading sensibly.
struct WeightStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Roughly what do you weigh?",
            subtitle: "Only so the calorie count is yours and not an average.",
            onNext: onNext
        ) {
            VStack(spacing: 16) {
                SegmentPicker(
                    options: [(value: .imperial, label: "lb"), (value: .metric, label: "kg")],
                    selection: $profile.units
                )

                VStack(spacing: 6) {
                    if profile.units == .imperial {
                        Picker("Weight", selection: weightPoundsBinding) {
                            ForEach(70...400, id: \.self) { pounds in
                                Text("\(pounds) lb").tag(pounds)
                            }
                        }
                    } else {
                        Picker("Weight", selection: weightKilogramsBinding) {
                            ForEach(35...200, id: \.self) { kg in
                                Text("\(kg) kg").tag(kg)
                            }
                        }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 170)
                .clipped()
                .ransomCard(padding: 10)
            }
        }
    }

    private var weightKilogramsBinding: Binding<Int> {
        Binding(
            get: { Int(profile.weightKg.rounded()) },
            set: { profile.weightKg = Double($0) }
        )
    }

    private var weightPoundsBinding: Binding<Int> {
        Binding(
            get: { Int((profile.weightKg * 2.20462).rounded()) },
            set: { profile.weightKg = Double($0) / 2.20462 }
        )
    }
}


// MARK: - Welcome

struct WelcomeStep: View {
    var onStart: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexIntroVideo(size: 320)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 12) {
                Text("Ransom")
                    .font(RansomFont.display(46))
                    .foregroundStyle(Palette.ink)

                Text("Move a little. Scroll a little.")
                    .font(RansomFont.title(21))
                    .foregroundStyle(Palette.brand)

                // Not push-ups. This screen runs before the exercise step, so
                // naming a movement here promises one the user has not picked
                // yet and may never pick: squats and walking are both on offer
                // two screens later. Every other line in the flow reads the
                // movement off the profile; this one could not, so it says the
                // category instead.
                Text("A quick set of exercise unlocks your apps. That's the whole idea - and you get stronger without ever planning a workout.")
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
            }
            .padding(.top, 10)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: "Let's go", action: onStart)
                Text("Takes about a minute.")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.7)) { appeared = true }
        }
    }
}


// MARK: - Age

struct AgeStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "How old are you?",
            subtitle: "Rex uses this to size your sets. That's all.",
            onNext: onNext
        ) {
            VStack(spacing: 18) {
                Picker("Age", selection: $profile.age) {
                    ForEach(13...80, id: \.self) { age in
                        Text("\(age)").font(RansomFont.title(22)).tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 190)
                .ransomCard(padding: 6)

                RexScene(pose: .idle, line: ageQuip, size: 96)
            }
        }
    }

    private var ageQuip: String {
        switch profile.age {
        case ..<20:   return "Starting early. Future you says thanks."
        case 20..<30: return "Perfect time to build a habit that sticks."
        case 30..<45: return "Great time to start. I mean that."
        default:      return "Steady beats hard. We'll go at your pace."
        }
    }
}
