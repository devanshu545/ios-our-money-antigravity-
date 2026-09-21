import Foundation
import Combine

/// Mirror of `ui/goals/GoalsScreen.kt` (GoalsViewModel).
final class GoalsViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository

    @Published private(set) var goals: [Goal] = []
    @Published private(set) var isSaving = false

    private var cancellables = Set<AnyCancellable>()

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        let repo = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        self.ledgerRepository = repo

        repo.$goals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.goals = $0 }
            .store(in: &cancellables)
    }

    func addGoal(name: String, targetAmountPaise: Int64, isPersonal: Bool, onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        ledgerRepository.addGoal(Goal(name: name, targetAmountPaise: targetAmountPaise, personal: isPersonal))
        Task { @MainActor [weak self] in
            self?.isSaving = false
            onSuccess()
        }
    }

    func editGoal(_ goal: Goal, newName: String, newTarget: Int64, onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        var updated = goal
        updated.name = newName
        updated.targetAmountPaise = newTarget
        ledgerRepository.updateGoal(updated)
        Task { @MainActor [weak self] in
            self?.isSaving = false
            onSuccess()
        }
    }

    func deleteGoal(_ goal: Goal) {
        ledgerRepository.deleteGoal(goalId: goal.id)
    }

    func addContribution(_ goal: Goal, amountPaise: Int64, onSuccess: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true
        var updated = goal
        updated.currentAmountPaise += amountPaise
        ledgerRepository.updateGoal(updated)
        Task { @MainActor [weak self] in
            self?.isSaving = false
            onSuccess()
        }
    }
}
