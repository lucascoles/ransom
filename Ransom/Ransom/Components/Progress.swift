import SwiftUI

/// Thin bar used at the top of the onboarding flow.
struct StepProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline)
                Capsule()
                    .fill(Palette.green)
                    .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
    }
}

/// The big daily-goal ring on the home screen.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 16
    var tint: Color = Palette.green
    var track: Color = Palette.hairline

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.75), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
    }
}

/// A number that rolls up to its value — used for rep counts and totals.
struct CountingNumber: View {
    var value: Int
    var font: Font
    var color: Color = Palette.ink

    @State private var displayed: Int = 0

    var body: some View {
        Text("\(displayed)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(displayed)))
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, newValue in animate(to: newValue) }
    }

    private func animate(to target: Int) {
        guard target != displayed else { return }
        let steps = min(abs(target - displayed), 24)
        guard steps > 0 else { return }
        let stride = Double(target - displayed) / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.03) {
                withAnimation(.snappy(duration: 0.12)) {
                    displayed = step == steps ? target : displayed + Int(stride.rounded())
                }
            }
        }
    }
}

/// Weekly bar chart. Deliberately hand-rolled — six bars don't need a charts dependency.
struct WeekBars: View {
    /// Sunday-first values paired with their day initial.
    var values: [(label: String, value: Double, isToday: Bool)]
    var tint: Color = Palette.green

    private var maxValue: Double { max(values.map(\.value).max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.surfaceAlt)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(item.isToday ? tint : tint.opacity(0.45))
                            .frame(height: max(6, 92 * (item.value / maxValue)))
                    }
                    .frame(height: 92)

                    Text(item.label)
                        .font(RansomFont.caption(11))
                        .foregroundStyle(item.isToday ? Palette.ink : Palette.inkFaint)
                }
            }
        }
    }
}
