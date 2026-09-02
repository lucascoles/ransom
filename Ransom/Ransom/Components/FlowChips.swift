import SwiftUI

/// A wrapping row of multi-select chips.
///
/// For secondary questions that don't deserve their own screen — the "and when?"
/// that now rides along with the hours question rather than costing a step.
struct FlowChips<Option: Hashable & Identifiable>: View {
    var options: [Option]
    @Binding var selection: Set<Option>
    var label: (Option) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                let isSelected = selection.contains(option)
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                        if isSelected { selection.remove(option) } else { selection.insert(option) }
                    }
                } label: {
                    Text(label(option))
                        .font(RansomFont.caption(14))
                        .foregroundStyle(isSelected ? Palette.green : Palette.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(isSelected ? Palette.greenSoft : Palette.surfaceAlt)
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Palette.green : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                }
                .pressable(scale: 0.95)
            }
        }
    }
}

/// Minimal wrapping layout. Chips wrap to the next line when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows = [Row()]
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width = x + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
}
