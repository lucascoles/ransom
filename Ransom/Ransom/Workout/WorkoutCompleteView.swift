import SwiftUI

/// The payoff screen. Confetti, a number that went up, and a door that just opened.
struct WorkoutCompleteView: View {
    var exercise: Exercise
    var reps: Int
    var minutes: Int
    var trigger: String?
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var appeared = false

    private var didEarn: Bool { minutes > 0 }

    var body: some View {
        ZStack {
            if didEarn {
                ConfettiBurst(isActive: appeared)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer()

                RexImage(pose: didEarn ? .cheer : .sad, size: 190)

                Text(didEarn ? "Unlocked." : "So close.")
                    .font(RansomFont.display(38))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)

                Text(subtitle)
                    .font(RansomFont.body(16))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                if didEarn {
                    statRow
                        .padding(.top, 26)
                }

                Spacer()

                VStack(spacing: 10) {
                    PrimaryButton(
                        title: didEarn ? primaryTitle : "Try again",
                        icon: didEarn ? "arrow.up.right" : "arrow.clockwise"
                    ) {
                        onDone()
                    }
                    if didEarn {
                        TextButton(title: "Stay in Ransom") { onDone() }
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

    private var primaryTitle: String {
        if let trigger { return "Back to \(trigger)" }
        return "Done"
    }

    private var subtitle: String {
        if didEarn {
            return "\(reps) \(exercise.title.lowercased()) banked. You've got \(minutes) minutes of scroll."
        }
        return "You stopped at \(reps). The reps still count toward today — the time doesn't."
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            miniStat(value: "\(minutes)m", label: "earned", tint: Palette.green)
            miniStat(value: "\(model.streak)", label: "day streak", tint: Palette.flame)
            miniStat(value: "\(model.todayReps)", label: "today", tint: Palette.violet)
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private func miniStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(RansomFont.title(24))
                .foregroundStyle(tint)
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
