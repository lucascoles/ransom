import FamilyControls
import SwiftUI

/// Wraps Apple's `FamilyActivityPicker` in Repp's chrome. The picker itself is a
/// system view we can't restyle, so the framing does the work.
struct AppPickerView: View {
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(\.dismiss) private var dismiss

    @State private var draft = FamilyActivitySelection()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                FamilyActivityPicker(selection: $draft)
            }
            .background(Palette.canvas)
            .navigationTitle("Choose apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(ReppFont.body(16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        screenTime.selection = draft
                        Haptics.success()
                        dismiss()
                    }
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.green)
                }
            }
            .onAppear { draft = screenTime.selection }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RexView(pose: .coach, size: 76, isAlive: false)
            Text("Pick the apps you want to have to earn. Rex will guard every one of them.")
                .font(ReppFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas)
    }
}
