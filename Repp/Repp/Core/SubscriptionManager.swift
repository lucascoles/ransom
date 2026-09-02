import Foundation
import Observation
import StoreKit

/// StoreKit 2 wrapper for Repp Pro.
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
            case .weekly: return "com.repp.app.pro.weekly"
            case .annual: return "com.repp.app.pro.annual"
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
            case .weekly: return "$5.99"
            case .annual: return "$39.99"
            }
        }

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

    /// "$0.77" — the annual rate expressed per week, which is the only fair way to
    /// compare it to the weekly plan.
    var annualPerWeek: String? {
        guard let annual = products[.annual] else { return "$0.77" }
        return (annual.price / 52).formatted(annual.priceFormatStyle)
    }

    /// How much less the annual costs than 52 weeks of the weekly rate. Computed
    /// from live StoreKit prices so it can't drift out of date if pricing changes.
    var annualSavingsPercent: Int? {
        let weeklyPrice = products[.weekly]?.price ?? 5.99
        let annualPrice = products[.annual]?.price ?? 39.99
        let yearOfWeekly = weeklyPrice * 52
        guard yearOfWeekly > 0, annualPrice < yearOfWeekly else { return nil }
        let ratio = (yearOfWeekly - annualPrice) / yearOfWeekly
        return Int((NSDecimalNumber(decimal: ratio).doubleValue * 100).rounded())
    }

    /// Only mentions a trial when the product actually carries an introductory offer.
    func trialDescription(for plan: Plan) -> String? {
        guard let offer = products[plan]?.subscription?.introductoryOffer,
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
        var byPlan: [Plan: Product] = [:]
        for product in loaded ?? [] {
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
