import DeviceActivity
import SwiftUI

/// Screen time, day by day, with this week measured against last.
///
/// The card this replaced compared today against the average the user typed in
/// during intake - a number they estimated once, months ago, that never moves.
/// It could only ever say the same thing twice. A trend compares them against
/// themselves, which is the only comparison that can show the habit changing.
///
/// Drawn by the report extension from iOS's own daily totals, for the same
/// reason as `ScreenTimeComparisonCard`: the threshold ladder it used to read is
/// inflated on iOS 26, and the exact figures cannot leave the extension. The
/// week and the average are worked out by `ScreenTimeSummary.Week`.
struct ScreenTimeTrendCard: View {
    @Environment(ScreenTimeManager.self) private var screenTime

    /// Header, a 110pt line and the weekday row. Fixed, as for every report.
    private static let reportHeight: CGFloat = 214

    @State private var now = Date()

    var body: some View {
        if screenTime.isAuthorized {
            // Fifteen days: this week, the week before it, and today.
            DeviceActivityReport(.trend, filter: .ransomDays(back: 14, until: now))
                .frame(height: Self.reportHeight)
                .ransomCard()
                .reportClock($now)
        }
    }
}
