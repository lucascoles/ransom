import SwiftUI

/// Naming a window and committing to it.
///
/// Three things and no more: what it is, when it runs, and a button that has to
/// be held. There is deliberately no app picker here - Ransom has one set of
/// guarded apps, chosen once, and a second per-rule list would mean the user
/// maintaining the same decision in two places and the shield having to work out
/// which one it is enforcing.
///
/// There is also no dial for how much harder it gets. It is double. A control for
/// how serious you are is a control you turn down at exactly the moment it starts
/// working.
struct RuleEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Nil when creating. Held rather than bound so nothing is written until the
    /// commit completes - a half-built rule must never start charging.
    var rule: FocusRule?
    /// A starter's values, prefilled for a rule that does not exist yet. Kept
    /// separate from `rule` so a template still reads as new: it commits rather
    /// than updates, and it has nothing to delete.
    var seed: FocusRule?

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var days: Set<Int> = []
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { rule != nil }

    private var exercise: Exercise { model.plan.exercise }
    private var baseReps: Int { model.basePlan.setTarget }
    private var ruledReps: Int { baseReps * FocusRule.difficultyMultiplier }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    timeCard
                    daysCard
                    costCard
                    if isEditing { deleteButton }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Palette.canvas)
            .safeAreaInset(edge: .bottom) {
                HoldToCommitButton(title: isEditing ? "Hold to update" : "Hold to commit",
                                   isEnabled: !trimmedName.isEmpty) {
                    save()
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 12)
                .background(Palette.canvas)
            }
            .navigationTitle(isEditing ? "Edit rule" : "New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(RansomFont.body(16))
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this rule?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("The window stops costing double straight away.")
            }
        }
    }

    // MARK: - Pieces

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("What are you protecting?")
            TextField("Gym time", text: $name)
                .font(RansomFont.title(22))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("During this time")
            VStack(spacing: 0) {
                timeRow("From", selection: $start)
                Divider().overlay(Palette.hairline)
                timeRow("To", selection: $end)
            }
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )

            // Said plainly rather than hidden behind an "overnight" switch nobody
            // would find. An end before a start is how you say "until late".
            if minutes(from: end) <= minutes(from: start) {
                Text("Runs overnight, into the next morning.")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private func timeRow(_ title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .font(RansomFont.body(16))
                .foregroundStyle(Palette.ink)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Palette.brand)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("On these days")
                Spacer()
                Text(FocusRuleFormat.days(days))
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkSoft)
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    dayCircle(weekday)
                }
            }
        }
    }

    private func dayCircle(_ weekday: Int) -> some View {
        // Empty means every day, so an untouched picker shows all seven lit and
        // reads as "always" rather than as a control nobody has filled in.
        let isOn = days.isEmpty || days.contains(weekday)
        return Button {
            Haptics.tick()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { toggle(weekday) }
        } label: {
            Text(Self.initials[weekday - 1])
                .font(RansomFont.headline(14))
                .foregroundStyle(isOn ? Palette.onBrand : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Circle().fill(isOn ? Palette.brand : Palette.surfaceAlt)
                )
        }
        .buttonStyle(.plain)
    }

    private static let initials = ["S", "M", "T", "W", "T", "F", "S"]

    private var costCard: some View {
        HStack(alignment: .top, spacing: 12) {
            RexImage(pose: .coach, size: 56, isAlive: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("Everything costs double")
                    .font(RansomFont.headline(15))
                    .foregroundStyle(Palette.ink)
                Text("While \(trimmedName.isEmpty ? "this" : trimmedName) is running, a set is \(ruledReps) \(exercise.title.lowercased()) instead of \(baseReps). Your bank and your goal don't change.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.brandSoft)
        )
    }

    private var deleteButton: some View {
        Button("Delete rule") { showDeleteConfirm = true }
            .font(RansomFont.body(15))
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(RansomFont.caption(12))
            .foregroundStyle(Palette.inkFaint)
    }

    // MARK: - State

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func toggle(_ weekday: Int) {
        // Expanding "every day" into a real set on first touch, or the first tap
        // would deselect one day and leave the other six unchanged - which is the
        // same thing on screen and a completely different rule underneath.
        if days.isEmpty { days = Set(1...7) }
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        if days.isEmpty { days = Set(1...7) }
    }

    private func load() {
        guard let source = rule ?? seed else {
            start = Self.date(fromMinutes: 17 * 60 + 30)
            end = Self.date(fromMinutes: 18 * 60 + 30)
            return
        }
        name = source.name
        start = Self.date(fromMinutes: source.startMinutes)
        end = Self.date(fromMinutes: source.endMinutes)
        days = source.days
    }

    private func save() {
        var updated = rule ?? FocusRule(name: "", startMinutes: 0, endMinutes: 0)
        updated.name = trimmedName
        updated.startMinutes = minutes(from: start)
        updated.endMinutes = minutes(from: end)
        updated.days = days.count == 7 ? [] : days
        updated.isEnabled = true

        var all = model.rules.rules
        if let index = all.firstIndex(where: { $0.id == updated.id }) {
            all[index] = updated
        } else {
            all.append(updated)
        }
        model.rules.rules = all
        model.rulesChanged()
        Haptics.celebrate()
        dismiss()
    }

    private func delete() {
        guard let rule else { return }
        model.rules.rules = model.rules.rules.filter { $0.id != rule.id }
        model.rulesChanged()
        Haptics.warning()
        dismiss()
    }

    private func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }
}
