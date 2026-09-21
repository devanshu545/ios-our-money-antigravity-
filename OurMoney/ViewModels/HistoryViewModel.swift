import Foundation
import Combine

/// Mirror of `ui/history/HistoryViewModel.kt`.
final class HistoryViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository

    @Published var searchQuery = ""
    @Published private(set) var partnerUser: User?
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var rows: [HistoryRow] = []

    struct HistoryRow: Identifiable, Hashable {
        let id: String
        let dateMillis: Int64
        let transaction: Transaction?
        let settlement: Settlement?
        var isPending: Bool { transaction?.isPending ?? settlement?.isPending ?? false }

        init(transaction: Transaction) {
            self.id = transaction.id
            self.dateMillis = transaction.dateMillis
            self.transaction = transaction
            self.settlement = nil
        }

        init(settlement: Settlement) {
            self.id = settlement.id
            self.dateMillis = settlement.dateMillis
            self.transaction = nil
            self.settlement = settlement
        }
    }

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        let partnerId = household.members.first { $0 != currentUser.id } ?? ""
        if !partnerId.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                let partner = await UserRepository().getUserSuspend(partnerId)
                await MainActor.run { self.partnerUser = partner }
            }
        }

        repo.$budgets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.budgets = $0 }
            .store(in: &cancellables)

        repo.$transactions
            .combineLatest(repo.$settlements, $searchQuery)
            .receive(on: DispatchQueue.main)
            .map { [weak self] txs, sets, query -> [HistoryRow] in
                guard let self else { return [] }
                let mappedSets = sets.map { s in
                    Transaction(
                        id: s.id,
                        amountPaise: s.amountPaise,
                        category: "Settlement",
                        dateMillis: s.dateMillis,
                        paidBy: s.paidBy,
                        createdBy: s.createdBy,
                        personal: false,
                        notes: s.notes,
                        type: .transfer,
                        paymentMethod: s.paymentMethod
                    )
                }
                let combined = (txs + mappedSets).sorted { $0.dateMillis > $1.dateMillis }
                var rows = combined.map { HistoryRow(transaction: $0) }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
                    rows = rows.filter { row in
                        let tx = row.transaction!
                        let amountStr = Formatters.plainAmountString(tx.amountPaise)
                        let dateStr = Formatters.dayFormatter.string(
                            from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000)).lowercased()
                        let scopeStr = tx.personal ? "personal" : "shared"
                        return terms.allSatisfy { term in
                            tx.category.lowercased().contains(term) ||
                            tx.notes.lowercased().contains(term) ||
                            tx.paymentMethod.lowercased().contains(term) ||
                            amountStr.contains(term) ||
                            dateStr.contains(term) ||
                            scopeStr.contains(term)
                        }
                    }
                }
                return rows
            }
            .assign(to: &$rows)
    }

    private var cancellables = Set<AnyCancellable>()

    func deleteTransaction(transactionId: String, isSettlement: Bool) {
        if isSettlement {
            ledgerRepository.deleteSettlement(settlementId: transactionId)
        } else {
            ledgerRepository.deleteTransaction(transactionId: transactionId)
        }
    }
}
