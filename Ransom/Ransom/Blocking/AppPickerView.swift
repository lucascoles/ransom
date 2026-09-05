import FamilyControls
import ManagedSettings
import SwiftUI

/// Wraps Apple's `FamilyActivityPicker` in Ransom's chrome. The picker itself is a
/// system view we can't restyle, so the framing does the work.
struct AppPickerView: View {
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = FamilyActivitySelection()
    /// Read once on appear rather than on every redraw: it comes from the App
    /// Group, and the row must not reshuffle itself under a finger mid-tap.
    @State private var suggestions: [ApplicationToken] = []
    @State private var measuredAt: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                SuggestedAppsRow(
                    selection: $draft,
                    tokens: suggestions,
                    namedApps: DistractingApp.allCases.filter(model.profile.distractingApps.contains),
                    measuredAt: measuredAt
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                FamilyActivityPicker(selection: $draft)
            }
            .background(Palette.canvas)
            .navigationTitle("Your apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(RansomFont.body(16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        screenTime.selection = draft
                        Haptics.success()
                        // Asked here rather than only in intake, because this is
                        // the moment it starts mattering. The shield's primary
                        // button hands off through a notification - the only
                        // route back to Ransom that Apple supports - so without
                        // permission that button silently does nothing, and
                        // anyone who skipped or refused the intake prompt gets a
                        // block screen they cannot act on.
                        Task { await NotificationManager.requestPermission() }
                        dismiss()
                    }
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.brand)
                }
            }
            .onAppear {
                draft = screenTime.selection
                let store = UsageSuggestionStore()
                // A stale ranking recommends the app they already dealt with, so
                // an old one is treated as no ranking at all.
                suggestions = store.isFresh ? store.suggestions : []
                measuredAt = store.measuredAt
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RexImage(pose: .coach, size: 76, isAlive: false)
            Text("Pick the apps that should take a set to open. Everything else stays exactly as it is.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas)
    }
}
