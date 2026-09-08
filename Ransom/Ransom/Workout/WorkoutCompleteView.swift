import SwiftUI

/// The payoff screen. Confetti, a number that went up, and a choice about it.
///
/// This is the moment the habit loop closes, so it does three things in order:
/// says you did it, shows what it got you, and names the small win on top (a
/// streak kept, a first set) so there's a reason to come back tomorrow.
///
/// The minutes are already banked by the time this appears. Spending them is a
/// separate decision offered here rather than made for the user: someone who did
/// a set at nine in the morning to build a balance should not be handed fifteen
/// minutes of Instagram they never asked for and a running clock.
struct WorkoutCompleteView: View {
    var exercise: Exercise
    var reps: Int
    var minutes: Int
    var trigger: String?
    /// Spend the minutes now and open the apps.
    var onUseNow: () -> Void
    /// Keep them in the bank and leave.
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var appeared = false

    private var didEarn: Bool { minutes > 0 }

    /// The set that was just recorded is already in the history, so "first set
    /// today" means today's reps are exactly this set's reps.
    private var isFirstSetToday: Bool { model.todayReps == reps }

    var body: some View {
        ZStack {
            if didEarn {
                ConfettiBurst(isActive: appeared)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer()

                RexImage(pose: didEarn ? .cheer : .coach, size: 190)
                    .scaleEffect(appeared ? 1 : 0.85)

                Text(didEarn ? "Banked!" : "Good effort.")
                    .font(RansomFont.display(38))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)

                Text(subtitle)
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)

                if didEarn {
                    statRow
                        .padding(.top, 26)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                }

                // Reserved whether or not there's a win line, so the stats don't
                // jump when one appears.
                Text(winLine ?? " ")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.flame)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 14)
                    .frame(minHeight: 20)

                Spacer()

                VStack(spacing: 10) {
                    if didEarn {
                        // Side by side and the same size, because this is a real
                        // choice between two reasonable things. A text link under a
                        // filled button reads as the way out of a dead end, not as
                        // the other half of a decision - and banking is the half
                        // the habit actually depends on.
                        HStack(spacing: 10) {
                            PrimaryButton(title: "Use \(minutes) min", icon: "hourglass") { onUseNow() }
                            SecondaryButton(title: "Save it", icon: "tray.and.arrow.down.fill") { onDone() }
                        }
                    } else {
                        PrimaryButton(title: "Go again", icon: "arrow.clockwise") { onDone() }
                        TextButton(title: "Not right now") { onDone() }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var subtitle: String {
        let move = exercise.title.lowercased()
        if didEarn {
            if let trigger {
                return "\(reps) \(move) done. \(Currency.coins(minutes)) banked - spend them on \(trigger) or keep them."
            }
            return "\(reps) \(move) done. \(Currency.coins(minutes)) in the bank."
        }
        return "\(reps) \(move) still count toward today. The apps stay closed this time."
    }

    /// The small win on top of the unlock, if there is one. Always one of the
    /// user's own numbers.
    private var winLine: String? {
        guard didEarn else { return nil }
        let streak = model.streak
        if model.history.count == 1 {
            return "First set ever. That's the hard one done."
        }
        if isFirstSetToday && streak > 1 {
            return "Streak kept: \(streak) days in a row."
        }
        if isFirstSetToday {
            return "First set of the day. Do one tomorrow and that's a streak."
        }
        return nil
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            miniStat(value: Currency.amount(minutes), label: "coins", tint: Palette.flame, showsCoin: true)
            miniStat(value: "\(model.streak)", label: "day streak", tint: Palette.flame)
            miniStat(value: "\(model.todayReps)", label: "reps today", tint: Palette.ink)
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private func miniStat(value: String, label: String, tint: Color, showsCoin: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                if showsCoin {
                    Image(Currency.symbolName)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(value)
                    .font(RansomFont.title(24))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}
