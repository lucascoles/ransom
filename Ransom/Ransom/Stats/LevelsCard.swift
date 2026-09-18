import CoreMotion
import DeviceActivity
import SwiftUI

/// A body in the middle, a level ring for each movement beside the muscles it
/// works most, and every muscle wearing the colour of its own level.
///
/// The Progress tab's lifetime number used to be one figure in a card, which
/// says how much has been done and nothing about where it is going. A level
/// per movement does both: the count is the lifetime, the ring is how close the
/// next level is, and the body shows what all of it has trained: each region
/// levels up from every movement that works it (`BodyRegion.weight`), and
/// every level is a new colour (`ExerciseLevel.tints`). Untrained is the
/// figure's own grey.
///
/// The figure is one illustration cut into layers (`media/levels-figure` in the
/// marketing folder has the colour-coded original and the script that cuts
/// it): an outline, the skin, and a mask per `BodyRegion`, each a template
/// image tinted here.
struct LevelsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime

    // Where the brain goes, measured off `LevelFigureOutline` (326 x 900): the
    // head runs from y=2 down to the neck's narrowest point at y=100, is widest
    // at 81px across, and is centred on the figure's axis. The glyph sits a
    // little above the middle of that, where a skull keeps its brain.
    // Both numbers were walked in against a render of the real asset: 70px
    // across broke the crown and spilled past the temples, 56 touched the
    // outline. 52 sits inside the skull with a margin all round.
    private static let headCentreY: CGFloat = 48.0 / 900.0
    private static let brainSpan: CGFloat = 52.0 / 326.0

    @State private var now = Date()

    /// Read once and refreshed after the pedometer back-fills, not observed:
    /// the log is UserDefaults, which SwiftUI cannot watch.
    @State private var lifetimeSteps = StepLog().lifetime

    /// Whether this person walks for minutes, or has walked before. Decides
    /// whether steps get a ring.
    private var walks: Bool {
        model.profile.exercises.contains(.steps) || lifetimeSteps > 0
    }

    private var movements: [Exercise] {
        // Push-ups and squats are always on offer (the swap row), so they always
        // have a ring. An empty steps ring for somebody who never turned walking
        // on would be noise.
        walks ? [.pushUps, .squats, .steps] : [.pushUps, .squats]
    }

    private func count(_ exercise: Exercise) -> Int {
        exercise == .steps ? lifetimeSteps : model.lifetimeReps(of: exercise)
    }

    /// Lifetime volume of every movement, for the body's regions.
    private var volumes: [Exercise: Int] {
        Dictionary(uniqueKeysWithValues: Exercise.allCases.map { ($0, count($0)) })
    }

    private func progress(_ exercise: Exercise) -> ExerciseLevel.Progress {
        ExerciseLevel.progress(count: count(exercise), for: exercise)
    }

    /// The level closest to going, as a share of the level it is in. A share
    /// rather than a raw count, or steps - thousands to go - would never be
    /// named next to push-ups with twelve.
    private var closest: (exercise: Exercise, progress: ExerciseLevel.Progress)? {
        movements.map { ($0, progress($0)) }.max { $0.1.fraction < $1.1.fraction }
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

    // MARK: - The body and the rings

    private static let stageHeight: CGFloat = 310

    private var stage: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                BodyFigure(tint: { region in
                    ExerciseLevel.tint(level: region.level(volumes: volumes))
                })
                .frame(height: h)
                .position(x: w / 2, y: h / 2)

                // Today's screen time, in the head. Drawn by the report
                // extension because total screen time exists in no other
                // process on the phone (see `BrainReport`), which is why a few
                // points of skull are hosting a whole remote view.
                if screenTime.isAuthorized {
                    let span = h * BodyFigure.aspect * Self.brainSpan
                    DeviceActivityReport(.brain, filter: .ransomDays(back: 0, until: now))
                        .id(now)
                        .frame(width: span, height: span)
                        .position(x: w / 2, y: h * Self.headCentreY)
                        .reportClock($now)
                }

                ForEach(movements, id: \.self) { exercise in
                    let spot = Self.spot(for: exercise)
                    LevelRing(exercise: exercise, progress: progress(exercise))
                        .position(x: spot.left ? LevelRing.diameter / 2 - 4 : w - LevelRing.diameter / 2 + 4,
                                  y: h * spot.y)
                }
            }
        }
        .frame(height: Self.stageHeight)
    }

    /// Each ring beside the muscles it colours, alternating sides so they never
    /// stack: push-ups at the chest, squats at the thighs, steps at the calves.
    /// Heights are fractions of the figure, which fills the stage top to bottom.
    private static func spot(for exercise: Exercise) -> (left: Bool, y: CGFloat) {
        switch exercise {
        case .pushUps: return (true, 0.27)
        case .squats:  return (false, 0.58)
        case .steps:   return (true, 0.84)
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

/// The figure: light grey everywhere, each region in its level's colour, and
/// the outline on top.
///
/// The same in light and dark mode on purpose. A pale body with dark lines reads
/// on both backgrounds, and a figure that changed with the theme would make the
/// level colours look different from one evening to the next.
private struct BodyFigure: View {
    let tint: (BodyRegion) -> UInt32?

    static let aspect: CGFloat = 326.0 / 900.0
    static let untrained = Color(red: 0.84, green: 0.85, blue: 0.83)
    static let line = Color(red: 0.10, green: 0.11, blue: 0.10)

    var body: some View {
        ZStack {
            layer("LevelFigureSkin", Self.untrained)
            ForEach(BodyRegion.allCases, id: \.self) { region in
                layer(region.assetName, tint(region).map { Color(hex: $0) } ?? Self.untrained)
                    .animation(.easeInOut(duration: 0.6), value: tint(region))
            }
            layer("LevelFigureOutline", Self.line)
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        // The rings carry the same information in words.
        .accessibilityHidden(true)
    }

    private func layer(_ name: String, _ colour: Color) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .foregroundStyle(colour)
    }
}

/// One movement's level: lifetime count in the middle, the ring filling toward
/// the next level around it, in the colour that level will turn the body.
private struct LevelRing: View {
    let exercise: Exercise
    let progress: ExerciseLevel.Progress

    static let diameter: CGFloat = 88
    private static let lineWidth: CGFloat = 7

    private var nextColour: Color {
        ExerciseLevel.tint(level: progress.level + 1).map { Color(hex: $0) } ?? Palette.brand
    }

    var body: some View {
        ZStack {
            Circle().fill(Palette.surface)
            Circle().stroke(Palette.hairline, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(nextColour, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.5), value: progress.fraction)

            VStack(spacing: 0) {
                ExerciseIcon(name: exercise.symbol, size: 13)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(height: 17)
                Text(Self.compact(progress.count))
                    .font(RansomFont.counter(21))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(progress.count)))
                Text("Lv. \(progress.level)")
                    .font(RansomFont.caption(11))
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(.horizontal, 11)
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
