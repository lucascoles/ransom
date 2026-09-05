import FamilyControls
import Foundation
import ManagedSettings

/// The apps this phone actually loses time to, ranked, for Rex to recommend.
///
/// There is no API that hands an app a list of the user's most-used apps. The
/// only place that data exists is inside a `DeviceActivityReport` extension,
/// which Apple sandboxes hard: no network, and its SwiftUI body is rendered in
/// its own process so nothing can be read back out of it by the app.
///
/// What *can* cross is an `ApplicationToken`. Tokens are `Codable` and opaque -
/// they name an app without telling us which app - so a report extension can rank
/// the last week's usage, write the top handful here, and the app can render them
/// with `Label(token)` and get the real icon and the real name on screen without
/// ever learning either. That is the whole trick behind a "we noticed you're on
/// these a lot" row, and it is how the app can suggest something it is not
/// allowed to know.
///
/// **Nothing writes this yet.** The report extension needs the Family Controls
/// entitlement, which needs a paid developer account, which this project does not
/// have - so the suggestions fall back to the apps the user named during intake.
/// When that target exists it writes here and the row lights up on its own.
public struct UsageSuggestionStore {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    /// Most-used first. Deliberately short: a recommendation of fifteen apps is
    /// a list, and a list is something to work through rather than agree with.
    public static let maximumSuggestions = 6

    /// The ranked tokens, or empty when nothing has measured them yet.
    public var suggestions: [ApplicationToken] {
        get {
            guard let data = defaults.data(forKey: RansomCore.Key.suggestedTokens),
                  let decoded = try? JSONDecoder().decode([ApplicationToken].self, from: data)
            else { return [] }
            return Array(decoded.prefix(Self.maximumSuggestions))
        }
        nonmutating set {
            let trimmed = Array(newValue.prefix(Self.maximumSuggestions))
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            defaults.set(data, forKey: RansomCore.Key.suggestedTokens)
            defaults.set(Date(), forKey: RansomCore.Key.suggestedAt)
        }
    }

    /// When the ranking was last measured. Shown to the user, because "your
    /// most-used apps" is a claim about a period and an unqualified claim about
    /// their own behaviour is the kind of thing that reads as a guess.
    public var measuredAt: Date? {
        defaults.object(forKey: RansomCore.Key.suggestedAt) as? Date
    }

    /// Stale suggestions are worse than none: a fortnight-old ranking recommends
    /// the app they already dealt with and misses the one they picked up since.
    public var isFresh: Bool {
        guard let measuredAt else { return false }
        return Date().timeIntervalSince(measuredAt) < 60 * 60 * 24 * 14
    }
}
