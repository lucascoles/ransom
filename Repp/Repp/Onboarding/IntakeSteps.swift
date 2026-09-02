import SwiftUI

// MARK: - Welcome

struct WelcomeStep: View {
    var onStart: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexView(pose: appeared ? .flex : .idle, size: 210)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 12) {
                Text("Repp")
                    .font(ReppFont.display(46))
                    .foregroundStyle(Palette.ink)

                Text("Earn your scroll.")
                    .font(ReppFont.title(21))
                    .foregroundStyle(Palette.green)

                Text("Instagram, TikTok and the rest stay locked until you move. Rex is the doorman.")
                    .font(ReppFont.body(16))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .padding(.top, 4)
            }
            .padding(.top, 10)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            Spacer()

            VStack(spacing: 12) {
                PrimaryButton(title: "Get started", action: onStart)
                Text("Takes about 60 seconds.")
                    .font(ReppFont.caption(12))
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

    var body: some View {
        StepScaffold(
            title: "What should Rex call you?",
            subtitle: "Optional. It just makes the nagging more personal.",
            buttonTitle: profile.firstName.isEmpty ? "Skip" : "Continue",
            onNext: onNext
        ) {
            VStack(spacing: 18) {
                TextField("First name", text: $profile.firstName)
                    .font(ReppFont.title(22))
                    .foregroundStyle(Palette.ink)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onNext)
                    .padding(.vertical, 6)
                    .reppCard()

                RexScene(
                    pose: .idle,
                    line: profile.firstName.isEmpty
                        ? "Or stay anonymous. I'll still block Instagram."
                        : "Nice to meet you, \(profile.firstName).",
                    size: 96
                )
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
            subtitle: "This calibrates your rep targets. Nothing else.",
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
            subtitle: "Rex adjusts how hard he pushes.",
            onNext: onNext
        ) {
            VStack(spacing: 18) {
                Picker("Age", selection: $profile.age) {
                    ForEach(13...80, id: \.self) { age in
                        Text("\(age)").font(ReppFont.title(22)).tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 190)
                .reppCard(padding: 6)

                RexScene(pose: .idle, line: ageQuip, size: 96)
            }
        }
    }

    private var ageQuip: String {
        switch profile.age {
        case ..<20:  return "Young joints. No excuses."
        case 20..<30: return "Prime rep-earning years."
        case 30..<45: return "Perfect age to start banking reps."
        default:      return "Consistency beats intensity. Always."
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
            subtitle: "Used to estimate the calories you burn earning your scroll.",
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
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
            content()
                .pickerStyle(.wheel)
                .frame(height: 170)
                .clipped()
        }
        .reppCard(padding: 10)
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
            title: "How often do you work out right now?",
            subtitle: "Be honest. Rex doesn't judge, he calibrates.",
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
