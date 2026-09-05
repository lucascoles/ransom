import SwiftUI

/// How many times the phone was reached for and turned away today.
///
/// Every other number in Ransom is about what the user did on purpose - sets
/// done, minutes earned, minutes spent. This one is about the reflex, which is
/// the thing they actually came here to change and the only thing they cannot
/// see for themselves. Eleven reaches for Instagram before lunch is not a number
/// anybody guesses correctly about their own day.
///
/// Stated flatly, without a verdict. "Rex stopped you 11 times" is a fact;
/// "you tried 11 times, come on" is a telling-off, and somebody who feels told
/// off deletes the app rather than the habit.
struct ReachesCard: View {
    @Environment(AppModel.self) private var model

    /// Re-read when the app comes back to the front. The shield writes these from
    /// another process while Ransom is not even running, so nothing here observes
    /// them - returning to the app is the only moment they can have changed.
    private var ranked: [(name: String, count: Int)] {
        _ = model.usageRevision
        return BlockCountStore().rankedToday
    }

    private var total: Int { ranked.reduce(0) { $0 + $1.count } }

    var body: some View {
        if let top = ranked.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RexImage(pose: .coach, size: 44, isAlive: false)
                    Text(headline(top: top))
                        .font(RansomFont.body(15))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The rest only earn their place once there is more than one, and
                // only the handful that matter - a full list turns a reality check
                // into an audit.
                if ranked.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(ranked.prefix(4), id: \.name) { entry in
                            HStack {
                                Text(entry.name)
                                    .font(RansomFont.body(14))
                                    .foregroundStyle(Palette.inkSoft)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(entry.count)x")
                                    .font(RansomFont.headline(14))
                                    .foregroundStyle(Palette.brand)
                            }
                        }
                    }
                    .padding(.leading, 54)
                }
            }
            .ransomCard()
        }
    }

    private func headline(top: (name: String, count: Int)) -> String {
        if ranked.count == 1 {
            return top.count == 1
                ? "You reached for \(top.name) once today. I caught it."
                : "You reached for \(top.name) \(top.count) times today. I caught every one."
        }
        return "You reached for your apps \(total) times today. \(top.name) was \(top.count) of them."
    }
}
