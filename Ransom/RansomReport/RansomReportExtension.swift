import DeviceActivity
import ExtensionKit
import SwiftUI

/// The only place on the phone that can see total screen time.
///
/// `DeviceActivityReport` is rendered by this extension in its own process and
/// displayed inside Ransom, which is how a number Apple will not hand to an app
/// still reaches the user's eyes. The app cannot read it: the extension is
/// sandboxed with no network and its view is composited in, not returned.
///
/// What it *can* do is write to the App Group, and that is how the figure gets
/// back to the rest of the app. That route is not documented and could be closed
/// by any iOS release, so nothing critical is built on it - the app always has
/// the `UsageMeter` ladder to fall back on, and this only ever improves the
/// number rather than being the only source of it.
@main
struct RansomReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { total in
            TotalActivityView(total: total)
        }
    }
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (TimeInterval) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TimeInterval {
        var total: TimeInterval = 0
        for await result in data {
            for await segment in result.activitySegments {
                total += segment.totalActivityDuration
            }
        }

        // The number crossing back into the app. Whole minutes, because a
        // fractional second of screen time is not a thing anyone needs.
        DeviceUsageStore().record(totalMinutes: Int(total / 60))
        return total
    }
}

/// Ransom's own rendering of the figure, so the one screen that shows real
/// system data does not look like a system panel dropped into the app.
struct TotalActivityView: View {
    let total: TimeInterval

    private var minutes: Int { Int(total / 60) }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(RansomPalette.brand))
            Text("on your phone today")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var label: String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
