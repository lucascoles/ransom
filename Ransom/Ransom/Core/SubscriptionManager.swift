import Foundation
import Observation
import StoreKit

/// StoreKit 2 wrapper for Ransom Pro.
///
/// Two products in one subscription group: a weekly rate that makes starting cheap,
/// and an annual rate priced far below 52 weeks of it. Same features either way —
/// the only difference is commitment, so the annual sits at the higher service level
/// and switching to it takes effect immediately rather than at renewal.
@Observable
final class SubscriptionManager {

    enum Plan: String, CaseIterable, Identifiable {
        case weekly
        case annual

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .weekly: return "com.ransom.app.pro.weekly"
            case .annual: return "com.ransom.app.pro.annual"
            }
        }

        var title: String {
            switch self {
            case .weekly: return "Weekly"
            case .annual: return "Annual"
            }
        }

        /// Fallback copy for when StoreKit can't be reached.
        var fallbackPrice: String {
            switch self {
            case .weekly: return "$4.99"
            case .annual: return "$49.99"
            }
        }

        /// Mirrors the introductory offer configured on the annual product. Used
        /// only when StoreKit hasn't answered, alongside `fallbackPrice`.
        ///
        /// Annual only, and that is the point. The trial is what makes the yearly
        /// plan the one worth choosing; offering it on both made the weekly plan
        /// free to try and the annual the one you commit to, which is backwards.
        /// A fallback that promised a trial on either would also flash one on the
        /// weekly row for the moment before StoreKit answers, and a promise shown
        /// and then withdrawn is worse than one never made.
        var fallbackTrial: String? {
            self == .annual ? "\(Plan.fallbackTrialDays) days free" : nil
        }

        /// The configured introductory offer, as a number, for when StoreKit
        /// hasn't answered. The one place the "3" is written.
        static let fallbackTrialDays = 3

        var periodLabel: String {
            switch self {
            case .weekly: return "week"
            case .annual: return "year"
            }
        }
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case failed(String)
    }

    private(set) var products: [Plan: Product] = [:]
    private(set) var isSubscribed = false
    private(set) var activePlan: Plan?
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isLoadingProducts = true

    /// Annual is pre-selected: it's the better deal for the user and the better
    /// retention outcome for us. The single highest-leverage thing to A/B here is
    /// flipping this to `.weekly`.
    var selectedPlan: Plan = .annual

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Display

    func product(for plan: Plan) -> Product? { products[plan] }

    func displayPrice(for plan: Plan) -> String {
        products[plan]?.displayPrice ?? plan.fallbackPrice
    }

    /// "$0.96" — the annual rate expressed per week, which is the only fair way to
    /// compare it to the weekly plan.
    var annualPerWeek: String? {
        guard let annual = products[.annual] else { return "$0.96" }
        return (annual.price / 52).formatted(annual.priceFormatStyle)
    }

    /// How much less the annual costs than 52 weeks of the weekly rate. Computed
    /// from live StoreKit prices so it can't drift out of date if pricing changes.
    var annualSavingsPercent: Int? {
        let weeklyPrice = products[.weekly]?.price ?? 4.99
        let annualPrice = products[.annual]?.price ?? 49.99
        let yearOfWeekly = weeklyPrice * 52
        guard yearOfWeekly > 0, annualPrice < yearOfWeekly else { return nil }
        let ratio = (yearOfWeekly - annualPrice) / yearOfWeekly
        return Int((NSDecimalNumber(decimal: ratio).doubleValue * 100).rounded())
    }

    /// Mentions a trial only when the loaded product actually carries one; falls back
    /// to the configured 3-day offer when StoreKit hasn't answered yet.
    func trialDescription(for plan: Plan) -> String? {
        guard let product = products[plan] else { return plan.fallbackTrial }
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let count = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day:   unit = count == 1 ? "day" : "days"
        case .week:  unit = count == 1 ? "week" : "weeks"
        case .month: unit = count == 1 ? "month" : "months"
        case .year:  unit = count == 1 ? "year" : "years"
        @unknown default: unit = "days"
        }
        return "\(count) \(unit) free"
    }

    /// The trial length in days, for the reminder screen and the reminder itself.
    /// Read off the same offer `trialDescription` reads, so the two can't
    /// disagree; nil when the plan carries no free trial.
    func trialDays(for plan: Plan) -> Int? {
        guard let product = products[plan] else {
            return plan == .annual ? Plan.fallbackTrialDays : nil
        }
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let count = offer.period.value
        switch offer.period.unit {
        case .day:   return count
        case .week:  return count * 7
        case .month: return count * 30
        case .year:  return count * 365
        @unknown default: return count
        }
    }

    /// Whether buying this plan now would start the free trial rather than
    /// charge straight away. Asked before the purchase, because the answer flips
    /// to "no" the moment it goes through. Optimistic when StoreKit has not
    /// answered, matching `trialDescription`.
    func isEligibleForTrial(_ plan: Plan) async -> Bool {
        guard let subscription = products[plan]?.subscription else { return true }
        guard trialDays(for: plan) != nil else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    /// The line Apple requires and users deserve: what you pay, when, and how often.
    func disclosure(for plan: Plan) -> String {
        let price = displayPrice(for: plan)
        let period = plan.periodLabel
        if let trial = trialDescription(for: plan) {
            return "\(trial), then \(price) per \(period). Cancel anytime."
        }
        return "\(price) per \(period), auto-renewing. Cancel anytime."
    }

    /// Describes whatever the user is currently paying, for the Settings screen.
    var activePlanLine: String {
        guard let activePlan else { return "Blocking needs Pro." }
        return "\(displayPrice(for: activePlan)) per \(activePlan.periodLabel) · cancel anytime"
    }

    // MARK: - Loading

    func loadProducts() async {
        await MainActor.run { isLoadingProducts = true }
        let loaded = try? await Product.products(for: Plan.allCases.map(\.productID))
        // Built with reduce rather than a mutating loop so the dictionary handed to
        // the main actor below is a `let`; capturing a `var` here is an error under
        // the Swift 6 language mode.
        let byPlan = (loaded ?? []).reduce(into: [Plan: Product]()) { byPlan, product in
            if let plan = Plan.allCases.first(where: { $0.productID == product.id }) {
                byPlan[plan] = product
            }
        }
        await MainActor.run {
            products = byPlan
            isLoadingProducts = false
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        guard let product = products[plan] else {
            purchaseState = .failed("That plan isn't available right now.")
            return false
        }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
                purchaseState = .idle
                return isSubscribed

            case .userCancelled:
                purchaseState = .idle
                return false

            case .pending:
                purchaseState = .failed("Your purchase is pending approval.")
                return false

            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            return false
        }
    }

    func restore() async {
        purchaseState = .purchasing
        try? await AppStore.sync()
        await refreshEntitlement()
        purchaseState = isSubscribed ? .idle : .failed("No active subscription found.")
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var found: Plan?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.revocationDate == nil,
                  let plan = Plan.allCases.first(where: { $0.productID == transaction.productID })
            else { continue }
            found = plan
        }
        // `Transaction.updates` delivers off the main thread; observable state
        // must only ever change on it.
        let resolved = found
        await MainActor.run {
            activePlan = resolved
            isSubscribed = resolved != nil
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, let transaction = try? self.checkVerified(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlement()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe):       return safe
        }
    }
}
