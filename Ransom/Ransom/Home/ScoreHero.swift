import SwiftUI

/// The one number at the top of the app.
///
/// Rex sits beside it rather than above it. He was carrying the whole top of the
/// screen on his own, which is a lot of room for a greeting - and a greeting is
/// not what somebody opens this app to find out.
struct ScoreHero: View {
    @Environment(AppModel.self) private var model
    var pose: RexPose
    var line: String

    private var score: DailyScore {
        _ = model.usageRevision
        return DailyScore.make(model: model, reaches: BlockCountStore().totalToday)
    }

    private var tint: Color {
        score.total >= DailyScore.good ? Palette.green : Palette.brand
    }

    var body: some View {
        let score = self.score
        return VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                // Capped, because the bubble grows with whatever Rex has to say
                // and the longest lines were pushing the score into the margin.
                // He is the greeting; the number is the reason people opened the
                // app, and it should not have to fight him for width.
                RexScene(pose: pose, line: line, size: 72)
                    .frame(maxWidth: 215, alignment: .leading)

                Spacer(minLength: 8)

                VStack(spacing: -4) {
                    Text("\(score.total)")
                        .font(RansomFont.display(52))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: Double(score.total)))
                    Text("today")
                        .font(RansomFont.caption(11))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 8) {
                pill("Focus", value: score.focus, icon: "hourglass")
                pill("Reps", value: score.reps, icon: model.plan.exercise.symbol)
                pill("Restraint", value: score.restraint, icon: "hand.raised.fill")
            }
        }
    }

    /// Each factor carries its own number, because a total on its own tells you
    /// how the day went and nothing about what to do next. Three tells you which
    /// one is dragging.
    private func pill(_ title: String, value: Int, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text("\(value)")
                    .font(RansomFont.headline(15))
                    .contentTransition(.numericText(value: Double(value)))
            }
            .foregroundStyle(value >= DailyScore.good ? Palette.green : Palette.inkSoft)

            Text(title)
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(value >= DailyScore.good ? Palette.green.opacity(0.35) : Palette.hairline,
                              lineWidth: 1)
        )
    }
}
