import SwiftUI

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

                Text("A quick set of push-ups unlocks your apps. That's the whole idea - and you get stronger without ever planning a workout.")
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

// MARK: - Name

struct NameStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        profile.firstName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        StepScaffold(
            title: "What should Rex call you?",
            subtitle: "Optional. Rex just likes cheering people on by name.",
            buttonTitle: "Continue",
            onNext: onNext
        ) {
            VStack(spacing: 18) {
                TextField("First name", text: $profile.firstName)
                    .font(RansomFont.title(22))
                    .foregroundStyle(Palette.ink)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onNext)
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

// MARK: - Gender

struct GenderStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Let's start simple",
            subtitle: "This sets your rep target. Nothing else.",
            showsButton: false,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Gender.allCases) { gender in
                    ChoiceCard(
                        title: gender.title,
                        isSelected: profile.gender == gender
                    ) {
                        profile.gender = gender
                        AutoAdvance.after(onNext)
                    }
                }
            }
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

// MARK: - Height & weight

struct BodyStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Height and weight",
            subtitle: "So Rex can tell you what your sets really burn.",
            onNext: onNext
        ) {
            VStack(spacing: 16) {
                SegmentPicker(
                    options: [(value: .imperial, label: "ft / lb"), (value: .metric, label: "cm / kg")],
                    selection: $profile.units
                )

                if profile.units == .imperial {
                    imperialPickers
                } else {
                    metricPickers
                }
            }
        }
    }

    private var imperialPickers: some View {
        HStack(spacing: 12) {
            wheel(label: "Height") {
                Picker("Height", selection: heightInchesBinding) {
                    ForEach(48...84, id: \.self) { inches in
                        Text("\(inches / 12)′ \(inches % 12)″").tag(inches)
                    }
                }
            }
            wheel(label: "Weight") {
                Picker("Weight", selection: weightPoundsBinding) {
                    ForEach(70...400, id: \.self) { pounds in
                        Text("\(pounds) lb").tag(pounds)
                    }
                }
            }
        }
    }

    private var metricPickers: some View {
        HStack(spacing: 12) {
            wheel(label: "Height") {
                Picker("Height", selection: heightCentimetresBinding) {
                    ForEach(120...220, id: \.self) { cm in
                        Text("\(cm) cm").tag(cm)
                    }
                }
            }
            wheel(label: "Weight") {
                Picker("Weight", selection: weightKilogramsBinding) {
                    ForEach(35...200, id: \.self) { kg in
                        Text("\(kg) kg").tag(kg)
                    }
                }
            }
        }
    }

    private func wheel<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
            content()
                .pickerStyle(.wheel)
                .frame(height: 170)
                .clipped()
        }
        .ransomCard(padding: 10)
    }

    // Bindings translate the stored metric values into whichever unit is showing.

    private var heightCentimetresBinding: Binding<Int> {
        Binding(
            get: { Int(profile.heightCm.rounded()) },
            set: { profile.heightCm = Double($0) }
        )
    }

    private var heightInchesBinding: Binding<Int> {
        Binding(
            get: { Int((profile.heightCm / 2.54).rounded()) },
            set: { profile.heightCm = Double($0) * 2.54 }
        )
    }

    private var weightKilogramsBinding: Binding<Int> {
        Binding(
            get: { Int(profile.weightKg.rounded()) },
            set: { profile.weightKg = Double($0) }
        )
    }

    private var weightPoundsBinding: Binding<Int> {
        Binding(
            get: { Int((profile.weightKg * 2.2046).rounded()) },
            set: { profile.weightKg = Double($0) / 2.2046 }
        )
    }
}

// MARK: - Fitness level

struct FitnessStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "How often do you work out?",
            subtitle: "No wrong answer. Rex sizes your sets from this, so honest is easiest.",
            showsButton: false,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(FitnessLevel.allCases) { level in
                    ChoiceCard(
                        title: level.title,
                        subtitle: level.subtitle,
                        icon: iconFor(level),
                        isSelected: profile.fitnessLevel == level
                    ) {
                        profile.fitnessLevel = level
                        AutoAdvance.after(onNext)
                    }
                }
            }
        }
    }

    private func iconFor(_ level: FitnessLevel) -> String {
        switch level {
        case .rarely:    return "tortoise.fill"
        case .sometimes: return "figure.run"
        case .often:     return "bolt.fill"
        }
    }
}
