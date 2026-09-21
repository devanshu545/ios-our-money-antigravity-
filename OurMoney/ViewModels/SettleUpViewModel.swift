import Foundation
import Combine

/// Mirror of `ui/settlement/SettleUpViewModel.kt`.
final class SettleUpViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository
    private let ledgerCalculator = LedgerCalculator()

    let partnerId: String
    @Published private(set) var partnerName = "Friend"

    private var editingSettlementId: String?
    private var loadedSettlement: Settlement?

    @Published private(set) var initialDataLoaded = false
    @Published var initialAmountStr = ""
    @Published var initialPaidByMe = true
    @Published var initialPaymentMethod = "UPI"
    @Published var initialNotes = ""
    @Published var initialDateMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    @Published private(set) var balance = LedgerBalance()
    @Published private(set) var settlements: [Settlement] = []
    @Published private(set) var isSaving = false
    /// Settable by views for client-side validation messages.
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        self.partnerId = household.members.first { $0 != currentUser.id } ?? ""
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        repo.$transactions
            .combineLatest(repo.$settlements)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transactions, sets in
                guard let self else { return }
                self.balance = self.ledgerCalculator.calculateNetBalance(
                    currentUserId: self.currentUser.id,
                    transactions: transactions,
                    settlements: sets
                )
                self.settlements = sets.sorted { $0.dateMillis > $1.dateMillis }
            }
            .store(in: &cancellables)

        if !partnerId.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                let partner = await UserRepository().getUserSuspend(partnerId)
                if let partner, !partner.name.isEmpty {
                    await MainActor.run { self.partnerName = partner.name }
                }
            }
        }
    }

    func loadSettlement(settlementId: String) {
        if editingSettlementId == settlementId { return }
        editingSettlementId = settlementId
        Task { [weak self] in
            guard let self else { return }
            let s = await self.ledgerRepository.getSettlement(settlementId: settlementId)
            await MainActor.run {
                self.loadedSettlement = s
                if let s {
                    self.initialAmountStr = Formatters.plainAmountString(s.amountPaise)
                    self.initialPaidByMe = s.paidBy == self.currentUser.id
                    self.initialPaymentMethod = s.paymentMethod.isEmpty ? "UPI" : s.paymentMethod
                    self.initialNotes = s.notes
                    self.initialDateMillis = s.dateMillis
                }
                self.initialDataLoaded = true
            }
        }
    }

    func setModeCreate() {
        editingSettlementId = nil
        loadedSettlement = nil
        initialDataLoaded = true
    }

    func clearError() {
        error = nil
    }

    func deleteSettlement(settlementId: String, onSuccess: @escaping () -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.ledgerRepository.deleteSettlement(settlementId: settlementId)
                    cont.resume()
                }
                await MainActor.run { onSuccess() }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func saveSettlement(amountPaise: Int64,
                        paidByCurrentUser: Bool,
                        paymentMethod: String,
                        notes: String,
                        dateMillis: Int64,
                        onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        error = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                guard amountPaise > 0 else { throw ValidationError("Amount must be greater than 0") }
                guard !self.partnerId.isEmpty else { throw ValidationError("No partner to settle with.") }

                let paidBy = paidByCurrentUser ? self.currentUser.id : self.partnerId
                let receivedBy = paidByCurrentUser ? self.partnerId : self.currentUser.id

                let settlement: Settlement
                if self.editingSettlementId != nil {
                    guard let existing = self.loadedSettlement else { throw ValidationError("Settlement not found") }
                    var updated = existing
                    updated.amountPaise = amountPaise
                    updated.paidBy = paidBy
                    updated.receivedBy = receivedBy
                    updated.paymentMethod = paymentMethod
                    updated.notes = notes
                    settlement = updated
                } else {
                    settlement = Settlement(
                        amountPaise: amountPaise,
                        paidBy: paidBy,
                        receivedBy: receivedBy,
                        dateMillis: dateMillis,
                        paymentMethod: paymentMethod,
                        notes: notes,
                        createdBy: self.currentUser.id
                    )
                }

                if self.editingSettlementId != nil {
                    self.ledgerRepository.updateSettlement(settlement)
                } else {
                    self.ledgerRepository.addSettlement(settlement)
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
