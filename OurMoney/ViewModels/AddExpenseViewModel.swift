import Foundation
import Combine

/// Mirror of `ui/expense/AddExpenseViewModel.kt`.
final class AddExpenseViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository
    private let userRepository = UserRepository()

    let otherUserId: String
    @Published private(set) var partnerName = "Friend"

    private var editingTransactionId: String?
    private var loadedTransaction: Transaction?

    @Published private(set) var initialDataLoaded = false
    @Published var initialAmountStr = ""
    @Published var initialCategory = ""
    @Published var initialPaymentMethod = "UPI"
    @Published var initialNotes = ""
    @Published var initialIsPersonal = false
    @Published var initialPaidByMe = true
    @Published var initialDateMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    @Published private(set) var isSaving = false
    /// Settable by views for client-side validation messages (Android mirrors this
    /// by writing validationError + viewModel.error directly from the screen).
    @Published var error: String?
    @Published private(set) var customCategories: [CustomCategory] = []

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        self.otherUserId = household.members.first { $0 != currentUser.id } ?? ""
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        repo.$customCategories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.customCategories = $0 }
            .store(in: &cancellables)

        if !otherUserId.isEmpty {
            Task { [weak self] in
                let partner = await UserRepository().getUserSuspend(otherUserId)
                if let partner, !partner.name.isEmpty {
                    await MainActor.run { self?.partnerName = partner.name }
                }
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    func loadTransaction(transactionId: String) {
        if editingTransactionId == transactionId { return }
        editingTransactionId = transactionId
        Task { [weak self] in
            guard let self else { return }
            let tx = await self.ledgerRepository.getTransaction(transactionId: transactionId)
            await MainActor.run {
                self.loadedTransaction = tx
                if let tx {
                    self.initialAmountStr = Formatters.plainAmountString(tx.amountPaise)
                    self.initialCategory = tx.category
                    self.initialPaymentMethod = tx.paymentMethod
                    self.initialNotes = tx.notes
                    self.initialIsPersonal = tx.personal
                    self.initialPaidByMe = tx.paidBy == self.currentUser.id
                    self.initialDateMillis = tx.dateMillis
                }
                self.initialDataLoaded = true
            }
        }
    }

    func setModeCreate() {
        editingTransactionId = nil
        loadedTransaction = nil
        initialDataLoaded = true
    }

    func clearError() {
        error = nil
    }

    static let standardCategories = ["Food & Dining", "Groceries", "Transport", "Shopping", "Entertainment",
                                     "Bills & Utilities", "Health", "Travel", "Education", "Misc"]

    func addCustomCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ledgerRepository.addCustomCategory(name: trimmed)
    }

    func deleteCustomCategory(categoryId: String) {
        ledgerRepository.deleteCustomCategory(categoryId: categoryId)
    }

    /// Saves (creates or updates) an expense. `onSuccess` runs on the main actor when
    /// Firestore accepted the write. Failures surface through `error` — never faked.
    func saveExpense(amountPaise: Int64,
                     category: String,
                     isPersonal: Bool,
                     paidByCurrentUser: Bool,
                     splitMethod: SplitMethod,
                     splits: [SplitAmount],
                     notes: String,
                     paymentMethod: String,
                     dateMillis: Int64,
                     onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        error = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                guard amountPaise > 0 else { throw ValidationError("Amount must be greater than 0") }
                guard !category.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError("Category is required") }

                let txId = self.editingTransactionId ?? UUID().uuidString
                let paidBy = paidByCurrentUser ? self.currentUser.id : self.otherUserId

                let tx: Transaction
                if self.editingTransactionId != nil {
                    guard let existing = self.loadedTransaction else { throw ValidationError("Transaction not found") }
                    var updated = existing
                    updated.amountPaise = amountPaise
                    updated.category = category
                    updated.paidBy = paidBy
                    updated.personal = isPersonal
                    updated.splitMethod = splitMethod
                    updated.splits = splits
                    updated.notes = notes
                    updated.paymentMethod = paymentMethod
                    updated.dateMillis = dateMillis
                    tx = updated
                } else {
                    tx = Transaction(
                        id: txId,
                        amountPaise: amountPaise,
                        category: category,
                        dateMillis: dateMillis,
                        paidBy: paidBy,
                        createdBy: self.currentUser.id,
                        personal: isPersonal,
                        splitMethod: splitMethod,
                        splits: splits,
                        notes: notes,
                        type: .expense,
                        paymentMethod: paymentMethod
                    )
                }

                if self.editingTransactionId != nil {
                    self.ledgerRepository.updateTransaction(tx)
                } else {
                    self.ledgerRepository.addTransaction(tx)
                }

                await MainActor.run {
                    self.isSaving = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }
}

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
