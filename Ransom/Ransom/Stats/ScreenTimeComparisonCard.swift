import DeviceActivity
import SwiftUI

/// Today's screen time against yesterday's, and one line about it.
///
/// The number above this card says how long the phone has been on today, which
/// answers "how am I doing" only if you happen to remember yesterday. This is
/// the comparison, which is the part people actually read.
///
/// **Drawn by the report extension, from the same minutes as the total above.**
/// It used to be worked out here, from two sources: an exact figure the report
/// extension wrote to the App Group, and the threshold ladder as a fallback. iOS
/// drops every App Group write that extension makes, so the exact figure never
/// arrived and this always showed the ladder - which iOS 26 inflates with
/// thresholds nobody reached. On a real phone it read "Today 10h" under a total
/// of 6h 20m. The extension is the only process that sees the real number, so it
/// draws the whole comparison, and the arithmetic lives in `ScreenTimeSummary`.
struct ScreenTimeComparisonCard: View {
    @Environment(ScreenTimeManager.self) private var screenTime

    /// The extension's view has no intrinsic height (see `ScreenTimeReportCard`),
    /// so the room is fixed: the percentage, two bars and up to three lines of
    /// copy on the narrowest phones, with a little to spare.
    private static let reportHeight: CGFloat = 166

    @State private var now = Date()

    var body: some View {
        if screenTime.isAuthorized {
            // Hourly, so the extension can stop yesterday at this time of day.
            DeviceActivityReport(.comparison, filter: .ransomDays(back: 1, until: now, hourly: true))
                .id(now)
                .frame(height: Self.reportHeight)
                .ransomCard()
                .reportClock($now)
        }
    }
}
