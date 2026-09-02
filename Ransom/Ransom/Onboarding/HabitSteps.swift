import SwiftUI

// MARK: - Which apps

struct AppsStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        StepScaffold(
            title: "What's eating your day?",
            subtitle: "Pick everything that pulls you in. You'll choose the exact apps later.",
            isButtonEnabled: !profile.distractingApps.isEmpty,
            onNext: onNext
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(DistractingApp.allCases) { app in
                    AppTile(
                        app: app,
                        isSelected: profile.distractingApps.contains(app)
                    ) {
                        toggle(app)
                    }
                }
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

private struct AppTile: View {
    var app: DistractingApp
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(app.emoji).font(.system(size: 30))
                Text(app.title)
                    .font(RansomFont.headline(15))
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.greenSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.green : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.green)
                        .padding(10)
                }
            }
        }
        .pressable(scale: 0.96)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - How much

struct ScrollLoadStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "How long, honestly?",
            subtitle: "Screen Time already knows. Say it out loud.",
            isButtonEnabled: profile.scrollLoad != nil,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(ScrollLoad.allCases) { load in
                    ChoiceCard(
                        title: load.title,
                        icon: "clock.fill",
                        isSelected: profile.scrollLoad == load
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            profile.scrollLoad = load
                        }
                    }
                }

                // "When" belongs with "how long" — same behaviour, one screen. It
                // also earns its keep: late-night is what turns on the surcharge.
                if profile.scrollLoad != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("And when does it get you?")
                            .font(RansomFont.headline(16))
                            .foregroundStyle(Palette.ink)

                        FlowChips(
                            options: TimeOfDay.allCases,
                            selection: $profile.peakTimes,
                            label: { "\($0.emoji)  \($0.shortTitle)" }
                        )
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
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

    private var load: ScrollLoad { profile.scrollLoad ?? .medium }
    private var daysPerYear: Int { max(1, load.daysPerYear) }
    private var hoursPerYear: Int { Int(load.hoursPerDay * 365) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexImage(pose: revealed ? .coach : .sad, size: 150)

            VStack(spacing: 6) {
                Text("At \(load.title.lowercased()) a day, that's")
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountingNumber(value: revealed ? daysPerYear : 0, font: RansomFont.display(78), color: Palette.brand)
                    Text("days")
                        .font(RansomFont.title(28))
                        .foregroundStyle(Palette.brand)
                }

                Text("of your year. \(hoursPerYear) hours, gone.")
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.top, 6)
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                bullet("Ransom doesn't delete the apps.", detail: "It puts a price on them.")
                bullet("The price is reps.", detail: "Push-ups, jacks, squats — your call.")
                bullet("You still scroll.", detail: "You just arrive slightly stronger.")
            }
            .padding(.top, 28)
            .padding(.horizontal, Metrics.screenPadding)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)

            Spacer()

            PrimaryButton(title: "Show me the fix", action: onNext)
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
                .foregroundStyle(Palette.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RansomFont.headline(15)).foregroundStyle(Palette.ink)
                Text(detail).font(RansomFont.body(14)).foregroundStyle(Palette.inkSoft)
            }
        }
    }
}
