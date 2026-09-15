import CoreMotion
import SwiftUI

/// Rex in the middle, a level ring for each movement around him.
///
/// The Progress tab's lifetime number used to be one figure in a card, which
/// says how much has been done and nothing about where it is going. A level
/// per movement does both: the count is the lifetime, the ring is how close the
/// next level is, and the line underneath names the one that is about to go.
///
/// Laid out for up to six movements, because more are coming. Positions are a
/// table by count rather than maths around a circle: Rex is taller than he is
/// wide, and rings evenly spaced on a circle land on his head and his feet.
struct LevelsCard: View {
    @Environment(AppModel.self) private var model

    /// Read once and refreshed after the pedometer back-fills, not observed:
    /// the log is UserDefaults, which SwiftUI cannot watch.
    @State private var lifetimeSteps = StepLog().lifetime

    private var movements: [Exercise] {
        // Push-ups and squats are always on offer (the swap row), so they always
        // have a ring. Steps only for somebody walking for minutes, or who has
        // walked before - an empty ring for a feature nobody turned on is noise.
        var list: [Exercise] = [.pushUps, .squats]
        if model.profile.exercises.contains(.steps) || lifetimeSteps > 0 { list.append(.steps) }
        return list
    }

    private func count(_ exercise: Exercise) -> Int {
        exercise == .steps ? lifetimeSteps : model.lifetimeReps(of: exercise)
    }

    private var levels: [(exercise: Exercise, progress: ExerciseLevel.Progress)] {
        movements.map { ($0, ExerciseLevel.progress(count: count($0), for: $0)) }
    }

    /// The level closest to going, as a share of the level it is in. A share
    /// rather than a raw count, or steps - thousands to go - would never be
    /// named next to push-ups with twelve.
    private var closest: (exercise: Exercise, progress: ExerciseLevel.Progress)? {
        levels.max { $0.progress.fraction < $1.progress.fraction }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Levels")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(model.lifetimeReps.formatted()) reps all time")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkSoft)
                    .contentTransition(.numericText(value: Double(model.lifetimeReps)))
            }

            stage

            if let closest {
                nextLine(closest.exercise, closest.progress)
            }
        }
        .ransomCard()
        .task { await backfillSteps() }
    }

    // MARK: - Rex and the rings

    private var stage: some View {
        let spots = Self.layout(count: levels.count)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RexImage(pose: .flex, size: Self.rexSize, isAlive: false)
                    .position(x: w / 2, y: h * spots.rexY)

                ForEach(Array(levels.enumerated()), id: \.element.exercise) { index, item in
                    let spot = spots.rings[index]
                    LevelRing(exercise: item.exercise, progress: item.progress)
                        .position(x: Self.x(for: spot, width: w), y: h * spot.y)
                }
            }
        }
        .frame(height: spots.height)
    }

    private static let rexSize: CGFloat = 124

    /// Where a ring goes. `side` is -1 left, 0 centre, 1 right; side rings sit
    /// as far out as the card allows (a few points into its padding), because
    /// Rex flexing is wide and anything nearer the middle lands on his arms.
    /// `inset` pulls a ring back in, which is how six of them make an arc.
    struct Spot {
        var side: Int
        var y: CGFloat
        var inset: CGFloat = 0
    }

    private static func x(for spot: Spot, width: CGFloat) -> CGFloat {
        let edge = LevelRing.diameter / 2 - 4 + spot.inset
        switch spot.side {
        case ..<0: return edge
        case 0:    return width / 2
        default:   return width - edge
        }
    }

    /// Ring positions, Rex's height and the stage's height, by count. A table
    /// rather than maths around a circle: Rex is taller than he is wide, and
    /// rings evenly spaced on a circle land on his head and his feet. Three
    /// sits as a podium, two at his shoulders and one at his feet.
    static func layout(count: Int) -> (height: CGFloat, rexY: CGFloat, rings: [Spot]) {
        switch count {
        case 0, 1:
            return (200, 0.5, [Spot(side: -1, y: 0.5)])
        case 2:
            return (200, 0.5, [Spot(side: -1, y: 0.5), Spot(side: 1, y: 0.5)])
        case 3:
            return (300, 0.33, [Spot(side: -1, y: 0.3), Spot(side: 1, y: 0.3),
                                Spot(side: 0, y: 0.84)])
        case 4:
            return (290, 0.5, [Spot(side: -1, y: 0.2), Spot(side: 1, y: 0.2),
                               Spot(side: -1, y: 0.8), Spot(side: 1, y: 0.8)])
        case 5:
            return (360, 0.36, [Spot(side: -1, y: 0.14, inset: 12), Spot(side: 1, y: 0.14, inset: 12),
                                Spot(side: -1, y: 0.5), Spot(side: 1, y: 0.5),
                                Spot(side: 0, y: 0.88)])
        default:
            return (380, 0.5, [Spot(side: -1, y: 0.14, inset: 12), Spot(side: 1, y: 0.14, inset: 12),
                               Spot(side: -1, y: 0.5), Spot(side: 1, y: 0.5),
                               Spot(side: -1, y: 0.86, inset: 12), Spot(side: 1, y: 0.86, inset: 12)])
        }
    }

    private func nextLine(_ exercise: Exercise, _ progress: ExerciseLevel.Progress) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.brand)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.brandSoft))
            Text("\(progress.remaining.formatted()) more \(exercise.title.lowercased()) to level \(progress.level + 1).")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Counts the week the phone still remembers, once motion access exists.
    /// Never asks for it: Progress is not the place for a permission prompt, and
    /// the Steps tab already asks when somebody chooses to walk.
    private func backfillSteps() async {
        guard CMPedometer.authorizationStatus() == .authorized else { return }
        await StepTracker().loadWeek()
        lifetimeSteps = StepLog().lifetime
    }
}

/// One movement's level: lifetime count in the middle, the ring filling toward
/// the next level around it.
private struct LevelRing: View {
    let exercise: Exercise
    let progress: ExerciseLevel.Progress

    static let diameter: CGFloat = 94
    private static let lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().fill(Palette.surface)
            Circle().stroke(Palette.hairline, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(Palette.brand, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.5), value: progress.fraction)

            VStack(spacing: 0) {
                ExerciseIcon(name: exercise.symbol, size: 14)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(height: 18)
                Text(Self.compact(progress.count))
                    .font(RansomFont.counter(22))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(progress.count)))
                Text("Lv. \(progress.level)")
                    .font(RansomFont.caption(11))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.title), level \(progress.level). \(progress.count.formatted()) \(exercise.unitLabel) so far, \(progress.remaining.formatted()) more to level \(progress.level + 1).")
    }

    /// Whole numbers up to 9,999, then "48.2k" and "1.2M", so a lifetime of
    /// steps still fits inside the ring.
    static func compact(_ value: Int) -> String {
        switch value {
        case ..<10_000: return value.formatted()
        case ..<1_000_000:
            return (Double(value) / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "k"
        default:
            return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
    }
}
