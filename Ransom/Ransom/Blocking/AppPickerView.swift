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
    /// What was already guarded when this sheet opened, while a commitment is
    /// running. The list can grow from here and cannot shrink.
    @State private var locked = FamilyActivitySelection()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                SuggestedAppsRow(
                    selection: $draft,
                    tokens: suggestions,
                    namedApps: DistractingApp.allCases.filter(model.profile.distractingApps.contains),
                    measuredAt: measuredAt,
                    locked: locked.applicationTokens
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
                        // A list you can shorten mid-craving is not a commitment.
                        // Apple's picker is a system view and its ticks cannot be
                        // disabled, so the rule is enforced on the way out: while
                        // a run is live the saved set is the union of what was
                        // there and whatever was added. Unticking is quietly
                        // undone rather than refused, because a picker that
                        // fights the user's finger is worse than one that simply
                        // does not forget.
                        screenTime.selection = model.profile.isCommitted
                            ? draft.merging(locked)
                            : draft
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
                locked = model.profile.isCommitted ? screenTime.selection : FamilyActivitySelection()
                let store = UsageSuggestionStore()
                // A stale ranking recommends the app they already dealt with, so
                // an old one is treated as no ranking at all.
                suggestions = store.isFresh ? store.suggestions : []
                measuredAt = store.measuredAt
            }
        }
    }

    /// Said out loud, before they try it. Finding out that an untick did not
    /// stick is the app appearing to be broken; being told the rule up front is
    /// the app holding them to something they chose.
    private var headerCopy: String {
        guard model.profile.isCommitted, !locked.applicationTokens.isEmpty
            || !locked.categoryTokens.isEmpty || !locked.webDomainTokens.isEmpty
        else {
            return "Pick the apps that should take a set to open. Everything else stays exactly as it is."
        }
        let days = model.profile.commitmentDaysLeft
        return "You can add apps here. The ones you've already committed to stay put for \(days) more day\(days == 1 ? "" : "s") - that was the deal you made with yourself."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RexImage(pose: .coach, size: 76, isAlive: false)
            Text(headerCopy)
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
