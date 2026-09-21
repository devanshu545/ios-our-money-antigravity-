import Foundation
import Combine

/// Mirror of `ui/analytics/AnalyticsScreen.kt` (AnalyticsViewModel + derived stats).
final class AnalyticsViewModel: ObservableObject {
    let currentUser: User
    let ledgerRepository: LedgerRepository

    struct Stats {
        var totalSpent: Int64 = 0
        var upiSpent: Int64 = 0
        var cashSpent: Int64 = 0
        var youPaid: Int64 = 0
        var partnerPaid: Int64 = 0
        var highestTransaction: Transaction?
        var categoryBreakdown: [(String, Int64)] = []
    }

    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var stats = Stats()

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        repo.$transactions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transactions in
                guard let self else { return }
                self.transactions = transactions
                self.stats = Self.compute(transactions: transactions, currentUserId: currentUser.id)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    static func compute(transactions: [Transaction], currentUserId: String) -> Stats {
        let activeTx = transactions.filter { !$0.isDeleted }
        let expenses = activeTx.filter { $0.type == .expense }

        var stats = Stats()
        stats.totalSpent = expenses.reduce(Int64(0)) { $0 + $1.amountPaise }
        stats.upiSpent = expenses.filter { $0.paymentMethod == "UPI" }.reduce(Int64(0)) { $0 + $1.amountPaise }
        stats.cashSpent = expenses.filter { $0.paymentMethod == "Cash" }.reduce(Int64(0)) { $0 + $1.amountPaise }
        stats.youPaid = expenses.filter { $0.paidBy == currentUserId }.reduce(Int64(0)) { $0 + $1.amountPaise }
        stats.partnerPaid = stats.totalSpent - stats.youPaid
        stats.highestTransaction = expenses.max { $0.amountPaise < $1.amountPaise }

        var byCategory: [String: Int64] = [:]
        for tx in expenses { byCategory[tx.category, default: 0] += tx.amountPaise }
        stats.categoryBreakdown = byCategory.sorted { $0.value > $1.value }
        return stats
    }
}
