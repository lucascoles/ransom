import DeviceActivity
import SwiftUI

/// Today's screen time, drawn as a brain in the figure's head.
///
/// It is the other half of what the body is saying: the muscles carry what the
/// reps have built, the brain carries what today on the phone is doing to the
/// thing they were for. One is earned over months, the other is spent by
/// lunchtime, and putting them in one figure is the only way the second reads
/// as a cost rather than as a statistic.
///
/// No number here. The glyph is a few points across inside the head, which is
/// no place for text, and the hours are already on screen in the card directly
/// below this one. The colour is the whole message.
///
/// **Drawn here because it cannot be drawn anywhere else.** The number is total
/// screen time, and this extension is the only process on the phone that can
/// see it; every attempt to pass it back to the app through the App Group is
/// dropped silently by iOS. The app supplies the one thing that travels the
/// other way, the day's allowance, which it mirrors into the App Group for us.
///
/// The colour is the message, so it is the only thing that moves: green while
/// the day is still young, tangerine as the allowance goes, red once it's gone.
/// Green is the app's earned state everywhere else and it means the same thing
/// here - this is the one screen where the user is winning by *not* doing
/// something, and the colour drains as they stop.
struct BrainReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .brain
    let content: (BrainToday) -> BrainView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> BrainToday {
        var total: TimeInterval = 0
        for await result in data {
            for await segment in result.activitySegments {
                total += segment.totalActivityDuration
            }
        }
        return BrainToday(
            minutes: Int(total / 60),
            allowance: UnlockLedger().allowanceMinutes
        )
    }
}

struct BrainToday {
    var minutes: Int
    /// Zero when the app has never written one, which means there is nothing to
    /// judge the day against and the brain says so by staying grey.
    var allowance: Int

    /// How much of today's allowance is gone, 0-1. Nil with no allowance.
    var spent: Double? {
        guard allowance > 0 else { return nil }
        return min(1, Double(minutes) / Double(allowance))
    }
}

struct BrainView: View {
    var day: BrainToday

    /// Green to tangerine to red, with the change front-loaded: the first hour
    /// of a four-hour allowance should already be visible, or the colour says
    /// nothing until the day is lost and there is no point telling someone then.
    private var tint: Color {
        guard let spent = day.spent else { return ReportPalette.inkFaint }
        switch spent {
        case ..<0.34:  return ReportPalette.green
        case ..<0.67:  return blend(ReportPalette.green, ReportPalette.brand, (spent - 0.34) / 0.33)
        case ..<1:     return blend(ReportPalette.brand, ReportPalette.danger, (spent - 0.67) / 0.33)
        default:       return ReportPalette.danger
        }
    }

    private var label: String {
        guard day.minutes > 0 else { return "Nothing yet today" }
        let hours = day.minutes / 60, minutes = day.minutes % 60
        let time = hours > 0 ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h") : "\(minutes)m"
        guard let spent = day.spent else { return "\(time) on your phone today" }
        if spent >= 1 { return "\(time) today, past your \(day.allowance / 60)h" }
        return "\(time) on your phone today"
    }

    var body: some View {
        // The organ on its own, not `brain.head.profile`: the figure supplies
        // the head, and a second head inside the first one looks like a
        // mistake. Resizable because the app sizes this to the skull it has to
        // sit in, and the extension is told that only as its own bounds.
        Image(systemName: "brain")
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(label)
    }

    private func blend(_ from: Color, _ to: Color, _ amount: Double) -> Color {
        let t = max(0, min(1, amount))
        let a = UIColor(from), b = UIColor(to)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: Double(r1 + (r2 - r1) * t),
                     green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t))
    }
}
