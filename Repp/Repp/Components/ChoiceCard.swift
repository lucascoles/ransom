import SwiftUI

/// The workhorse of the onboarding flow: a tall tap target with an optional icon,
/// a title, a supporting line, and a clear selected state.
struct ChoiceCard: View {
    var title: String
    var subtitle: String?
    var icon: String?
    var emoji: String?
    var isSelected: Bool
    /// Multi-select shows a checkbox; single-select shows nothing until chosen.
    var allowsMultiple: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 14) {
                if let emoji {
                    Text(emoji).font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(isSelected ? Palette.greenSoft : Palette.surfaceAlt))
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? Palette.green : Palette.inkSoft)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(isSelected ? Palette.greenSoft : Palette.surfaceAlt))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ReppFont.headline(17))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(ReppFont.body(13))
                            .foregroundStyle(Palette.inkSoft)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if allowsMultiple {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Palette.green : Palette.hairline)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(isSelected ? Palette.greenSoft : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.green : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .pressable(scale: 0.98)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
    }
}

/// Compact horizontal segmented control (used for units, timeframes).
struct SegmentPicker<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(ReppFont.caption(14))
                        .foregroundStyle(selection == option.value ? Palette.ink : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == option.value ? Palette.surface : .clear)
                                .shadow(color: .black.opacity(selection == option.value ? 0.06 : 0), radius: 5, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surfaceAlt))
    }
}
