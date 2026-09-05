import FamilyControls
import ManagedSettings
import SwiftUI

/// Rex's shortlist, sitting above the system picker: "these are the ones, aren't
/// they."
///
/// Apple's picker is a flat alphabetical list of every app on the phone, which
/// asks the user to do the diagnosis themselves at the exact moment they are
/// least inclined to be honest about it. Naming the apps first turns the job from
/// an audit into a yes.
///
/// Two sources, in order of how much they know:
///  * The phone's own usage ranking, when a `DeviceActivityReport` extension has
///    measured it. Real icons, real names, and one tap adds them - see
///    `UsageSuggestionStore` for how tokens carry that across without the app
///    ever learning which app is which.
///  * Otherwise the apps the user named during intake. No token exists for those,
///    so they cannot be added on a tap - Apple only mints a token through its own
///    picker - and the row can only point at the list below. Still worth showing:
///    it is their own answer, handed back at the moment it is useful.
struct SuggestedAppsRow: View {
    @Binding var selection: FamilyActivitySelection
    /// Ranked most-used first. Empty falls the view back to the named apps.
    var tokens: [ApplicationToken]
    var namedApps: [DistractingApp]
    var measuredAt: Date?

    var body: some View {
        if !tokens.isEmpty {
            measured
        } else if !namedApps.isEmpty {
            named
        }
    }

    // MARK: - Measured

    private var measured: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Rex would start here",
                    detail: "The apps you spent the most time in\(period). Tap to guard them.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        tile(for: token)
                    }
                }
                .padding(.horizontal, 20)
            }
            // The scroll view is full-bleed so the row can run off the edge and
            // read as scrollable, which a row that stops at the margin does not.
            .padding(.horizontal, -20)
        }
    }

    private func tile(for token: ApplicationToken) -> some View {
        let isPicked = selection.applicationTokens.contains(token)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isPicked {
                    selection.applicationTokens.remove(token)
                    Haptics.tap()
                } else {
                    selection.applicationTokens.insert(token)
                    Haptics.success()
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    // The system draws the icon; we only get to frame it. Which is
                    // the point - it is the real app, not our copy of a logo.
                    Label(token)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 44))
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Image(systemName: isPicked ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 19, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isPicked ? Palette.green : Palette.brand)
                        .offset(x: 5, y: 5)
                }
                .frame(width: 64, height: 64, alignment: .topLeading)

                Label(token)
                    .labelStyle(.titleOnly)
                    .font(RansomFont.caption(11))
                    .foregroundStyle(isPicked ? Palette.ink : Palette.inkSoft)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(.plain)
    }

    /// Only claimed when it can be backed up. An unqualified "your most-used
    /// apps" is a claim about somebody's own behaviour, and the moment it is
    /// wrong it is the app that looks like it is guessing.
    private var period: String {
        guard let measuredAt,
              let days = Calendar.current.dateComponents([.day], from: measuredAt, to: Date()).day
        else { return "" }
        return days <= 1 ? " this week" : " recently"
    }

    // MARK: - Named during intake

    private var named: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("You told Rex about these",
                    detail: "Find them below and they're handled.")

            // Chips, not buttons. There is no token for an app the user has not
            // picked in Apple's own picker, so tapping one could not add it and a
            // control that does nothing is worse than a label that says something.
            NamedAppChips(apps: namedApps)
        }
    }

    // MARK: - Shared

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(RansomFont.headline(15))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The named apps, wrapping onto as many rows as they need.
private struct NamedAppChips: View {
    var apps: [DistractingApp]

    var body: some View {
        // Eight apps at most, so a fixed two-column-ish wrap beats the layout
        // gymnastics of a real flow layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(apps) { app in
                HStack(spacing: 6) {
                    Text(app.emoji)
                        .font(.system(size: 14))
                    Text(app.title)
                        .font(RansomFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.surfaceAlt))
            }
        }
    }
}
