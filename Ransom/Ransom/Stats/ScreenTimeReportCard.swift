import Combine
import DeviceActivity
import FamilyControls
import SwiftUI

/// Real screen time for the whole phone, which is a number Apple will not give
/// an app.
///
/// Everything else in Ransom counts what Ransom guards. This counts the phone.
/// It works by hosting `DeviceActivityReport`, a view whose contents are built
/// and rendered by our report extension in a separate process and composited in
/// here - the app never sees the figure, it only makes room for it. That is the
/// entire supported surface for device-wide usage, and it is why this is a card
/// rather than a number the rest of the app can quote.
struct ScreenTimeReportCard: View {
    @Environment(ScreenTimeManager.self) private var screenTime

    /// Whether the report has ever come back with anything.
    ///
    /// The card cannot ask the report how tall it wants to be - it is drawn by
    /// another process - so the host reserves the room, and reserving room for
    /// five apps before there is one leaves a card that is mostly nothing. It
    /// has to be on screen at some size for the extension to run at all, so the
    /// first pass gets a short one and the full height arrives with the data.
    /// A fixed 318pt, and deliberately not conditional on anything.
    ///
    /// Every attempt to be smart here has failed, each in its own way. Sizing
    /// from the last render's row count lags a render, so a quiet morning locked
    /// the card small for the day. Starting short "until the report has data"
    /// deadlocks: the short card is what the report draws into, and nothing
    /// redraws it once the data lands, so it stays short forever.
    ///
    /// The view is drawn by another process, has no intrinsic height, and clips
    /// rather than scrolls when the frame is too small - losing the total off the
    /// top and leaving a middle slice that reads as missing data. So the frame is
    /// a constant, sized to the five rows the extension caps its list at.
    private static let reportHeight: CGFloat = 318

    /// When the filter was last worked out. See `ReportClock`.
    @State private var now = Date()

    /// Today, from midnight. A `.daily` segment over a shorter interval is what
    /// makes the report a running total rather than yesterday's finished one.
    private var filter: DeviceActivityFilter {
        .ransomDays(back: 0, until: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.brand)
                Text("Screen time")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
            }

            if screenTime.isAuthorized {
                DeviceActivityReport(.totalActivity, filter: filter)
                    // The report brings its own intrinsic size and it is not
                    // always sensible, so the card decides how much room it gets
                    // rather than being pushed around by another process's view.
                    .frame(height: Self.reportHeight)
            } else {
                Text("Turn on Screen Time and Rex can show you the whole picture, not just the apps he's guarding.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Counted by iOS across every app, guarded or not.")
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkFaint)
        }
        .ransomCard()
        .reportClock($now)
    }
}

extension DeviceActivityFilter {
    /// Whole days of this iPhone's screen time, one `.daily` segment each, from
    /// midnight `back` days ago up to `until`. Every Ransom report asks the same
    /// way, so the three cards on Progress always add up the same minutes.
    static func ransomDays(back: Int, until now: Date) -> DeviceActivityFilter {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -back, to: today) ?? today
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: max(start, now))),
            users: .all,
            devices: .init([.iPhone])
        )
    }
}

/// Keeps a report's "now" current.
///
/// A report's filter is fixed when it is built, and SwiftUI only rebuilds it
/// when something the view reads changes. The filter used to call `Date()`
/// inline and read nothing else, so leaving Ransom in the background overnight
/// brought the morning back to yesterday's interval: yesterday's screen time
/// under "today", until the app was quit and reopened. `now` is state, moved on
/// whenever the answer could have changed: the screen appearing, the app coming
/// back to the front, and midnight.
private struct ReportClock: ViewModifier {
    @Binding var now: Date
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { tick() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tick() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: RunLoop.main)
            ) { _ in now = Date() }
    }

    /// Not within half a minute of the last one. A new filter makes the
    /// extension draw the report again, and appearing straight after being
    /// built would draw every card twice for nothing.
    private func tick() {
        let date = Date()
        guard date.timeIntervalSince(now) > 30
                || !Calendar.current.isDate(date, inSameDayAs: now) else { return }
        now = date
    }
}

extension View {
    func reportClock(_ now: Binding<Date>) -> some View {
        modifier(ReportClock(now: now))
    }
}
