import DeviceActivity
import ManagedSettings
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
        TotalActivityReport { day in
            TotalActivityView(day: day)
        }
    }
}

/// What the report hands back: the day's total, and the apps that took it.
struct DayActivity {
    var totalMinutes: Int
    var apps: [AppUsage]

    struct AppUsage: Identifiable {
        let id = UUID()
        var token: ApplicationToken?
        var name: String
        var minutes: Int
    }
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (DayActivity) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> DayActivity {
        var total: TimeInterval = 0
        var byApp: [String: (token: ApplicationToken?, seconds: TimeInterval)] = [:]

        for await result in data {
            for await segment in result.activitySegments {
                total += segment.totalActivityDuration
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? "Other"
                        let seconds = app.totalActivityDuration
                        let existing = byApp[name]?.seconds ?? 0
                        byApp[name] = (app.application.token, existing + seconds)
                    }
                }
            }
        }

        // Five is enough to recognise the day. A full list is a Settings screen,
        // and this is meant to be read at a glance on the way past.
        let apps = byApp
            .map { DayActivity.AppUsage(token: $0.value.token, name: $0.key,
                                        minutes: Int($0.value.seconds / 60)) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
            .prefix(5)

        DeviceUsageStore().record(totalMinutes: Int(total / 60))
        return DayActivity(totalMinutes: Int(total / 60), apps: Array(apps))
    }
}

/// Ransom's own rendering of the figure, so the one screen showing real system
/// data does not look like a system panel dropped into the app.
struct TotalActivityView: View {
    let day: DayActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: -2) {
                Text(clock(day.totalMinutes))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(RansomPalette.brand))
                Text("today")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(day.apps) { app in
                HStack(spacing: 10) {
                    if let token = app.token {
                        Label(token)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 26))
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        // A bar against the day's worst offender, not against the
                        // clock: the question this answers is "which of these is
                        // eating the day", and every app looks tiny next to 24h.
                        GeometryReader { geometry in
                            Capsule()
                                .fill(Color(RansomPalette.brand))
                                .frame(width: geometry.size.width * share(app), height: 5)
                        }
                        .frame(height: 5)
                    }

                    Text(clock(app.minutes))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func share(_ app: DayActivity.AppUsage) -> Double {
        let top = day.apps.first?.minutes ?? 0
        guard top > 0 else { return 0 }
        return max(0.04, Double(app.minutes) / Double(top))
    }

    private func clock(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
