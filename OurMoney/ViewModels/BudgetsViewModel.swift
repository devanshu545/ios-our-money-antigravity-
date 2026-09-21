import Foundation
import Combine

/// Mirror of `ui/budgets/BudgetsScreen.kt` (BudgetsViewModel).
final class BudgetsViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository

    let partnerId: String

    @Published var selectedMonth: Date = Date()
    @Published var selectedScope: BudgetScope = .all

    @Published private(set) var budgetState: ComprehensiveBudgetState?
    @Published private(set) var isSaving = false
    @Published private(set) var customCategories: [CustomCategory] = []

    private var cancellables = Set<AnyCancellable>()

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        self.partnerId = household.members.first { $0 != currentUser.id } ?? ""
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        repo.$budgets
            .combineLatest(repo.$transactions, $selectedMonth, $selectedScope)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] budgets, transactions, month, scope in
                guard let self else { return }
                self.budgetState = BudgetAnalytics.buildState(
                    budgets: budgets,
                    transactions: transactions,
                    selectedMonth: month,
                    selectedScope: scope,
                    currentUser: currentUser,
                    partnerId: self.partnerId
                )
            }
            .store(in: &cancellables)

        repo.$customCategories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.customCategories = $0 }
            .store(in: &cancellables)
    }

    func previousMonth() {
        if let prev = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = prev
        }
    }

    func nextMonth() {
        if let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = next
        }
    }

    func addCustomCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ledgerRepository.addCustomCategory(name: trimmed)
    }

    func deleteCustomCategory(categoryId: String) {
        ledgerRepository.deleteCustomCategory(categoryId: categoryId)
    }

    func saveBudget(existing: Budget?, category: String, limitAmountPaise: Int64, isPersonal: Bool,
                    onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        Task { [weak self] in
            guard let self else { return }
            let monthYear = BudgetAnalytics.monthYearFormatter.string(from: self.selectedMonth)
            if var budget = existing {
                budget.category = category
                budget.limitAmountPaise = limitAmountPaise
                budget.personal = isPersonal
                budget.monthYear = monthYear
                self.ledgerRepository.updateBudget(budget)
            } else {
                let budget = Budget(
                    category: category,
                    limitAmountPaise: limitAmountPaise,
                    personal: isPersonal,
                    createdBy: self.currentUser.id,
                    monthYear: monthYear
                )
                self.ledgerRepository.addBudget(budget)
            }
            await MainActor.run {
                self.isSaving = false
                onSuccess()
            }
        }
    }

    func deleteBudget(budgetId: String) {
        ledgerRepository.deleteBudget(budgetId: budgetId)
    }
}
