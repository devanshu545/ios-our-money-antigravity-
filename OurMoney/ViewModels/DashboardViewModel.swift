import Foundation
import Combine

struct DashboardState {
    var isLoading: Bool = true
    var transactions: [Transaction] = []
    var balance = LedgerBalance()
    var currentUser: User
    var household: Household
    var partnerUser: User?

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
    }
}

/// Mirror of `ui/dashboard/DashboardViewModel.kt`.
final class DashboardViewModel: ObservableObject {
    @Published var state: DashboardState

    let ledgerRepository: LedgerRepository
    private let ledgerCalculator = LedgerCalculator()
    private let userRepository = UserRepository()
    private var cancellables = Set<AnyCancellable>()

    init(currentUser: User, household: Household) {
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo
        self.state = DashboardState(currentUser: currentUser, household: household)

        let partnerId = household.members.first { $0 != currentUser.id } ?? ""

        // Fetch partner profile once (same as Android's suspend getUser).
        if !partnerId.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                let partner = await UserRepository().getUserSuspend(partnerId)
                await MainActor.run {
                    self.state.partnerUser = partner
                    self.state.isLoading = false
                }
            }
        }

        repo.$transactions
            .combineLatest(repo.$settlements)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transactions, settlements in
                guard let self else { return }
                let balance = self.ledgerCalculator.calculateNetBalance(
                    currentUserId: currentUser.id,
                    transactions: transactions,
                    settlements: settlements
                )
                self.state.transactions = transactions
                self.state.balance = balance
                self.state.isLoading = false
            }
            .store(in: &cancellables)
    }

    func deleteTransaction(transactionId: String) {
        ledgerRepository.deleteTransaction(transactionId: transactionId)
    }
}
