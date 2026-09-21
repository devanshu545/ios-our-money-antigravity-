import Foundation
import FirebaseFirestore
import Combine

/// Real-time repository mirroring `data/LedgerRepository.kt`.
/// Every collection is observed with snapshot listeners so changes made by the Android
/// client appear here live (and vice versa). Same paths, same fields, same sorting.
final class LedgerRepository: ObservableObject {
    let householdId: String
    let currentUserId: String

    private let db = Firestore.firestore()
    private var householdRef: DocumentReference { db.collection("households").document(householdId) }

    // Combined, published state (mirrors the Kotlin `combine(sharedFlow, personalFlow)`).
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var settlements: [Settlement] = []
    @Published private(set) var goals: [Goal] = []
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var customCategories: [CustomCategory] = []
    /// Last listener error, surfaced to the UI instead of failing silently.
    @Published private(set) var listenError: String?

    private var listeners: [ListenerRegistration] = []
    private var sharedTransactions: [Transaction] = []
    private var personalTransactions: [Transaction] = []

    init(householdId: String, currentUserId: String) {
        self.householdId = householdId
        self.currentUserId = currentUserId
        start()
    }

    deinit { removeAllListeners() }

    private var isAttached = false
    private func start() {
        guard !isAttached else { return }
        isAttached = true
        let txRef = householdRef.collection("transactions")

        // Shared transactions: personal == false
        listeners.append(txRef.whereField("personal", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.listenError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.sharedTransactions = self.decode(snapshot) { tx, doc in
                    tx.isPending = doc.metadata.hasPendingWrites()
                    return tx.isDeleted ? nil : tx
                }
                self.publishTransactions()
            })

        // Personal transactions: personal == true && createdBy == me
        listeners.append(txRef.whereField("personal", isEqualTo: true)
            .whereField("createdBy", isEqualTo: currentUserId)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.listenError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.personalTransactions = self.decode(snapshot) { tx, doc in
                    tx.isPending = doc.metadata.hasPendingWrites()
                    return tx.isDeleted ? nil : tx
                }
                self.publishTransactions()
            })

        // Settlements ordered by dateMillis DESC
        listeners.append(householdRef.collection("settlements")
            .order(by: "dateMillis", descending: true)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.listenError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.settlements = self.decode(snapshot) { s, doc in
                    s.isPending = doc.metadata.hasPendingWrites()
                    return s
                }
            })

        // Goals: shared + personal (mine), sorted createdAt DESC
        listeners.append(householdRef.collection("goals")
            .whereField("personal", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.listenError = error.localizedDescription; return }
                guard let snapshot else { return }
                self.goals = self.decode(snapshot) { g, doc in
                    g.isPending = doc.metadata.hasPendingWrites()
                    return g
                }
                self.publishGoals()
            })
        listeners.append(householdRef.collection("goals")
            .whereField("personal", isEqualTo: true)
            .whereField("createdBy", isEqualTo: currentUserId)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.listenError = error.localizedDescription; return }
                guard let snapshot else { return }
                self.personalGoals = self.decode(snapshot) { g, doc in
                    g.isPending = doc.metadata.hasPendingWrites()
                    return g
                }
                self.publishGoals()
            })

        // Budgets: shared + personal (mine), sorted createdAt DESC
        listeners.append(householdRef.collection("budgets")
            .whereField("personal", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.listenError = error.localizedDescription; return }
                guard let snapshot else { return }
                self.budgets = self.decode(snapshot) { b, doc in
                    b.isPending = doc.metadata.hasPendingWrites()
                    return b
                }
                self.publishBudgets()
            })
        listeners.append(householdRef.collection("budgets")
            .whereField("personal", isEqualTo: true)
            .whereField("createdBy", isEqualTo: currentUserId)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.listenError = error.localizedDescription; return }
                guard let snapshot else { return }
                self.personalBudgets = self.decode(snapshot) { b, doc in
                    b.isPending = doc.metadata.hasPendingWrites()
                    return b
                }
                self.publishBudgets()
            })

        // Custom categories ordered by name ASC (no personal filter, like Android)
        listeners.append(householdRef.collection("categories")
            .order(by: "name", descending: false)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.listenError = error.localizedDescription; return }
                guard let snapshot else { return }
                self.customCategories = self.decode(snapshot) { c, _ in c }
            })
    }

    private var personalGoals: [Goal] = []
    private var personalBudgets: [Budget] = []

    private func publishTransactions() {
        transactions = (sharedTransactions + personalTransactions)
            .sorted { $0.dateMillis > $1.dateMillis }
    }

    private func publishGoals() {
        goals = (goals.filter { !$0.personal } + personalGoals).sorted { $0.createdAt > $1.createdAt }
    }

    private func publishBudgets() {
        budgets = (budgets.filter { !$0.personal } + personalBudgets).sorted { $0.createdAt > $1.createdAt }
    }

    /// Decodes documents with the same leniency as Android's try/catch `toObject` (bad docs skipped).
    private func decode<T: Decodable>(_ snapshot: QuerySnapshot,
                                      transform: (T, QueryDocumentSnapshot) -> T?) -> [T] {
        snapshot.documents.compactMap { doc -> T? in
            guard let value = try? doc.data(as: T.self) else { return nil }
            return transform(value, doc)
        }
    }

    func removeAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isAttached = false
    }

    // MARK: - Transactions

    func getTransaction(transactionId: String) async -> Transaction? {
        try? await householdRef.collection("transactions").document(transactionId)
            .getDocument().data(as: Transaction.self)
    }

    func addTransaction(_ transaction: Transaction) {
        var newTransaction = transaction
        newTransaction.createdBy = currentUserId
        let ref = householdRef.collection("transactions").document(newTransaction.id)
        Task { [ref] in
            do { try await ref.setData(from: newTransaction) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func updateTransaction(_ transaction: Transaction) {
        let ref = householdRef.collection("transactions").document(transaction.id)
        Task { [ref] in
            do { try await ref.setData(from: transaction) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func deleteTransaction(transactionId: String) {
        householdRef.collection("transactions").document(transactionId).delete()
    }

    // MARK: - Settlements

    func getSettlement(settlementId: String) async -> Settlement? {
        try? await householdRef.collection("settlements").document(settlementId)
            .getDocument().data(as: Settlement.self)
    }

    func addSettlement(_ settlement: Settlement) {
        var newSettlement = settlement
        newSettlement.createdBy = currentUserId
        let ref = householdRef.collection("settlements").document(newSettlement.id)
        Task { [ref] in
            do { try await ref.setData(from: newSettlement) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func updateSettlement(_ settlement: Settlement) {
        let ref = householdRef.collection("settlements").document(settlement.id)
        Task { [ref] in
            do { try await ref.setData(from: settlement) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func deleteSettlement(settlementId: String) {
        householdRef.collection("settlements").document(settlementId).delete()
    }

    // MARK: - Goals

    func addGoal(_ goal: Goal) {
        var newGoal = goal
        newGoal.createdBy = currentUserId
        let ref = householdRef.collection("goals").document(newGoal.id)
        Task { [ref] in
            do { try await ref.setData(from: newGoal) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func updateGoal(_ goal: Goal) {
        let ref = householdRef.collection("goals").document(goal.id)
        Task { [ref] in
            do { try await ref.setData(from: goal) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func deleteGoal(goalId: String) {
        householdRef.collection("goals").document(goalId).delete()
    }

    // MARK: - Budgets

    func addBudget(_ budget: Budget) {
        var newBudget = budget
        newBudget.createdBy = currentUserId
        let ref = householdRef.collection("budgets").document(newBudget.id)
        Task { [ref] in
            do { try await ref.setData(from: newBudget) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func updateBudget(_ budget: Budget) {
        let ref = householdRef.collection("budgets").document(budget.id)
        Task { [ref] in
            do { try await ref.setData(from: budget) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func deleteBudget(budgetId: String) {
        householdRef.collection("budgets").document(budgetId).delete()
    }

    // MARK: - Custom categories

    func addCustomCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = CustomCategory(name: trimmed, createdBy: currentUserId)
        let ref = householdRef.collection("categories").document(category.id)
        Task { [ref] in
            do { try await ref.setData(from: category) }
            catch { await MainActor.run { self.listenError = error.localizedDescription } }
        }
    }

    func deleteCustomCategory(categoryId: String) {
        householdRef.collection("categories").document(categoryId).delete()
    }

    // MARK: - Reset (Settings screen)

    /// Deletes all shared transactions, my personal transactions and all settlements.
    /// iOS chunks writes into batches of 400 (Firestore limit is 500 ops/batch);
    /// the Android implementation submits a single batch and fails on large datasets.
    func resetAllTransactions() async throws {
        var ops: [DocumentReference] = []

        let sharedDocs = try await householdRef.collection("transactions")
            .whereField("personal", isEqualTo: false).getDocuments()
        ops.append(contentsOf: sharedDocs.documents.map(\.reference))

        let personalDocs = try await householdRef.collection("transactions")
            .whereField("personal", isEqualTo: true)
            .whereField("createdBy", isEqualTo: currentUserId).getDocuments()
        ops.append(contentsOf: personalDocs.documents.map(\.reference))

        let settlementDocs = try await householdRef.collection("settlements").getDocuments()
        ops.append(contentsOf: settlementDocs.documents.map(\.reference))

        var batch = db.batch()
        var count = 0
        for ref in ops {
            batch.deleteDocument(ref)
            count += 1
            if count >= 400 {
                try await batch.commit()
                batch = db.batch()
                count = 0
            }
        }
        if count > 0 { try await batch.commit() }
    }
}
