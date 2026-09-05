import SwiftUI

/// The user's focus windows, on the home screen where they will be seen.
///
/// Buried in Settings a rule is a preference, and a preference is something you
/// forget you set. On the home screen it is a standing reminder of a promise,
/// sitting next to the balance it makes more expensive.
struct RulesSection: View {
    @Environment(AppModel.self) private var model

    @State private var editing: FocusRule?
    @State private var isCreating = false

    private var rules: [FocusRule] {
        _ = model.ruleRevision
        return model.rules.rules.sorted { $0.startMinutes < $1.startMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your rules")
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if let active = model.activeRule {
                    Text("\(active.name) is on")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.brand)
                }
            }

            Text("Name the hour that matters and the phone costs double while it runs.")
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    newRuleCard
                    ForEach(rules) { rule in
                        RuleCard(rule: rule, isActive: rule.isActive())
                            .onTapGesture {
                                Haptics.tap()
                                editing = rule
                            }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -Metrics.screenPadding)
        }
        .sheet(isPresented: $isCreating) {
            RuleEditorSheet(rule: nil)
        }
        .onAppear(perform: debugOpenEditor)
        // A rule starting is the one price change nothing else triggers: no tap,
        // no purchase, just the clock reaching 5:30. Without this the set screen
        // would keep quoting the old number until something else happened to
        // redraw it, which is exactly when the user is watching.
        .task {
            var wasActive = model.activeRule?.id
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                let nowActive = model.rules.activeRule()?.id
                guard nowActive != wasActive else { continue }
                wasActive = nowActive
                model.rulesChanged()
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditorSheet(rule: rule)
        }
    }

    /// `-RansomRuleEditor 1` opens the editor straight away. Same reason as
    /// `-RansomWorkout`: there is no UI-test target to tap the card, and the sheet
    /// is otherwise below the fold and unreachable from a screenshot.
    private func debugOpenEditor() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "RansomRuleEditor") else { return }
        isCreating = true
        #endif
    }

    private var newRuleCard: some View {
        Button {
            Haptics.tap()
            isCreating = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.brand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.brandSoft))
                Text("New rule")
                    .font(RansomFont.headline(14))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 130, height: 128)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Palette.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

/// One committed window.
private struct RuleCard: View {
    var rule: FocusRule
    var isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "lock.fill" : "calendar")
                    .font(.system(size: 11, weight: .bold))
                Text(isActive ? "Running" : dayLabel)
                    .font(RansomFont.caption(11))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Palette.onBrand : Palette.inkFaint)

            Spacer(minLength: 0)

            Text(rule.name)
                .font(RansomFont.headline(16))
                .foregroundStyle(isActive ? Palette.onBrand : Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(timeLabel)
                .font(RansomFont.caption(12))
                .foregroundStyle(isActive ? Palette.onBrand.opacity(0.85) : Palette.inkSoft)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 150, height: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(isActive ? Palette.brand : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: isActive ? 0 : 1)
        )
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    private var timeLabel: String {
        "\(FocusRuleFormat.clock(rule.startMinutes)) - \(FocusRuleFormat.clock(rule.endMinutes))"
    }

    private var dayLabel: String {
        FocusRuleFormat.days(rule.days)
    }
}

/// Shared formatting, so a rule reads the same on the card, in the editor and in
/// any copy that quotes it.
enum FocusRuleFormat {
    static func clock(_ minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.hour().minute())
    }

    /// "Every day", "Weekdays", or the short names. Named groups first because
    /// "Mon, Tue, Wed, Thu, Fri" is five things to read and "Weekdays" is one.
    static func days(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { symbols[safe: $0 - 1] }.joined(separator: ", ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
