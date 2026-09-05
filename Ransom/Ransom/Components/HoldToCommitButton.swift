import SwiftUI

/// A button that has to be held down.
///
/// A tap is something a thumb does on the way past. Holding for a second is short
/// enough not to be a chore and long enough that nobody does it by accident, and
/// it makes committing feel like the small deliberate act it is meant to be.
struct HoldToCommitButton: View {
    var title: String
    var isEnabled: Bool = true
    /// How long the hold lasts. Declared before `action` so a trailing closure
    /// still reads as the action rather than binding backwards to this.
    var duration: Double = 1.0
    var action: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    /// The hold itself. The fill is only an animation - reading completion off it
    /// fires the moment the state is set rather than when the bar arrives, which
    /// is how a "hold to commit" button ends up committing on tap.
    @State private var hold: Task<Void, Never>?


    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(isEnabled ? Palette.brandSoft : Palette.surfaceAlt)

            // The fill is the feedback. Without it a long press is just a button
            // that ignores you for a second.
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.brand)
                    .frame(width: geometry.size.width * progress)
            }

            Text(title)
                .font(RansomFont.headline(17))
                .foregroundStyle(progress > 0.5 ? Palette.onBrand : (isEnabled ? Palette.brand : Palette.inkFaint))
        }
        .frame(height: Metrics.buttonHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isHolding else { return }
                    isHolding = true
                    Haptics.tap()
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                    hold = Task {
                        try? await Task.sleep(for: .seconds(duration))
                        guard !Task.isCancelled else { return }
                        Haptics.success()
                        action()
                    }
                }
                .onEnded { _ in
                    guard isHolding else { return }
                    isHolding = false
                    // Letting go early abandons it, or the hold means nothing.
                    hold?.cancel()
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
        )
        .onDisappear { hold?.cancel() }
        .disabled(!isEnabled)
    }
}
