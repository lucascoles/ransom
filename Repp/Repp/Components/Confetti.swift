import SwiftUI

/// Lightweight celebration burst for finishing a set. No dependencies, no images —
/// a few dozen coloured chips driven by a single TimelineView clock.
struct ConfettiBurst: View {
    var isActive: Bool
    var pieceCount: Int = 46

    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let delay: Double
        let drift: CGFloat
        let spin: Double
        let color: Color
        let size: CGFloat
        let isCircle: Bool
    }

    @State private var pieces: [Piece] = []
    @State private var start: Date = .now

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isActive)) { context in
                let elapsed = context.date.timeIntervalSince(start)
                ZStack {
                    ForEach(pieces) { piece in
                        let t = max(0, elapsed - piece.delay)
                        let progress = min(t / 2.4, 1)
                        let y = -40 + (geo.size.height + 120) * CGFloat(progress * progress * 0.85 + progress * 0.15)
                        let x = geo.size.width * piece.x + piece.drift * CGFloat(sin(t * 2.2))

                        Group {
                            if piece.isCircle {
                                Circle().fill(piece.color)
                            } else {
                                RoundedRectangle(cornerRadius: 2).fill(piece.color)
                            }
                        }
                        .frame(width: piece.size, height: piece.size * (piece.isCircle ? 1 : 1.6))
                        .rotationEffect(.degrees(piece.spin * t))
                        .position(x: x, y: y)
                        .opacity(progress > 0.9 ? (1 - progress) * 10 : (t > 0 ? 1 : 0))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear(perform: seed)
        .onChange(of: isActive) { _, active in
            if active { seed() }
        }
    }

    private func seed() {
        let colors: [Color] = [Palette.green, Palette.lime, Palette.flame, Palette.violet, Color(hex: 0xFFD84D)]
        pieces = (0..<pieceCount).map { _ in
            Piece(
                x: CGFloat.random(in: 0.02...0.98),
                delay: Double.random(in: 0...0.5),
                drift: CGFloat.random(in: -34...34),
                spin: Double.random(in: -320...320),
                color: colors.randomElement() ?? Palette.green,
                size: CGFloat.random(in: 6...11),
                isCircle: Bool.random()
            )
        }
        start = .now
    }
}
