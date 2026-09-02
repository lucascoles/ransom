import FamilyControls
import Foundation
import ManagedSettings

/// Persists the user's chosen apps/categories in the App Group so the app, the
/// shield extensions and the monitor extension all shield exactly the same set.
public struct BlockedSelectionStore {
    private static let key = "repp.blocked.selection"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = ReppCore.defaults) {
        self.defaults = defaults
    }

    public var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return decoded
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }

    public var isEmpty: Bool {
        let selection = self.selection
        return selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    public var count: Int {
        let selection = self.selection
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    // MARK: - Enforcement

    /// Puts Rex in the doorway of every selected app.
    public func applyShield() {
        let store = ManagedSettingsStore(named: .repp)
        let selection = self.selection

        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    /// Steps aside for the duration of earned time.
    public func removeShield() {
        let store = ManagedSettingsStore(named: .repp)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    /// Re-applies or lifts the shield to match the ledger. Safe to call from anywhere.
    public func reconcile(ledger: UnlockLedger = UnlockLedger()) {
        if ledger.isUnlocked {
            removeShield()
        } else {
            applyShield()
        }
    }
}
