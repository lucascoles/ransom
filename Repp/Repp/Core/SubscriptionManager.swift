import Foundation
import Observation
import StoreKit

/// StoreKit 2 wrapper for Repp Pro. One product, one price, no tiers.
@Observable
final class SubscriptionManager {
    static let monthlyProductID = "com.repp.app.pro.monthly"

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var isSubscribed = false
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isLoadingProducts = true

    private var updatesTask: Task<Void, Never>?

    init() {
        // Start listening before loading, so a transaction that lands mid-launch
        // is never missed.
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Display

    /// "$5.99" from the store, falling back to the intended price if StoreKit is
    /// unreachable (no network, or the product isn't configured yet).
    var displayPrice: String {
        product?.displayPrice ?? "$5.99"
    }

    var pricePerMonthLine: String {
        "\(displayPrice) per month · cancel anytime"
    }

    /// Only mentions a trial when the product actually carries an introductory offer.
    var trialDescription: String? {
        guard let offer = product?.subscription?.introductoryOffer,
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
        return "\(count)-\(unit) free trial"
    }

    // MARK: - Loading

    func loadProducts() async {
        await MainActor.run { isLoadingProducts = true }
        let loaded = try? await Product.products(for: [Self.monthlyProductID])
        await MainActor.run {
            product = loaded?.first
            isLoadingProducts = false
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            purchaseState = .failed("Subscriptions aren't available right now.")
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
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.monthlyProductID, transaction.revocationDate == nil {
                active = true
            }
        }
        // `Transaction.updates` delivers off the main thread; observable state
        // must only ever change on it.
        let result = active
        await MainActor.run { isSubscribed = result }
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
