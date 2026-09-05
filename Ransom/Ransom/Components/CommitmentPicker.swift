import SwiftUI

/// How long a difficulty is being committed to, chosen right where the difficulty
/// is chosen.
///
/// Splitting these apart, as the intake first did, let someone pick Beast mode and
/// then quietly commit to it for the shortest run on a later screen - two decisions
/// that only mean anything together. Together they read as one sentence: this hard,
/// for this long.
///
/// Upgrading is always allowed and simply restarts the clock at the new tier.
/// Dropping back is what the commitment exists to prevent.
struct CommitmentPicker: View {
    @Binding var days: Int?
    var tint: Color = Palette.brand

    static let minimumDays = 5
    static let maximumDays = 90

    @State private var isCustom = false

    private var chosen: Int { days ?? CommitmentLength.five.days }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(CommitmentLength.allCases) { length in
                    chip(title: length.shortTitle, isOn: !isCustom && days == length.days) {
                        isCustom = false
                        days = length.days
                    }
                }
                chip(title: "Custom", isOn: isCustom) {
                    isCustom = true
                    days = max(Self.minimumDays, chosen)
                }
            }

            if isCustom {
                VStack(spacing: 6) {
                    Text("\(chosen) days")
                        .font(RansomFont.headline(17))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: Double(chosen)))

                    Slider(
                        value: Binding(
                            get: { Double(chosen) },
                            set: { value in
                                let stepped = Int(value.rounded())
                                // Only on a real step change, or one drag fires a
                                // tap per frame.
                                if stepped != days { Haptics.tick() }
                                days = stepped
                            }
                        ),
                        in: Double(Self.minimumDays)...Double(Self.maximumDays),
                        step: 1
                    )
                    .tint(tint)

                    Text("\(Self.minimumDays) days minimum")
                        .font(RansomFont.caption(11))
                        .foregroundStyle(Palette.inkFaint)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isCustom)
        .onAppear {
            if let days, !CommitmentLength.allCases.map(\.days).contains(days) { isCustom = true }
        }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82), action)
        } label: {
            Text(title)
                .font(RansomFont.headline(14))
                .foregroundStyle(isOn ? .white : Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isOn ? tint : Palette.surfaceAlt)
                )
        }
        .pressable(scale: 0.96)
    }
}
