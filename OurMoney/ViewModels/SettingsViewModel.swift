import Foundation
import Combine
import FirebaseFirestore

/// Mirror of `ui/settings/SettingsViewModel.kt`.
final class SettingsViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    let ledgerRepository: LedgerRepository

    @Published private(set) var partnerName = "Friend"
    @Published private(set) var isDisconnecting = false
    @Published private(set) var isResetting = false
    @Published private(set) var error: String?

    let authRepository: AuthRepository

    init(currentUser: User, household: Household, authRepository: AuthRepository) {
        self.currentUser = currentUser
        self.household = household
        self.authRepository = authRepository
        self.ledgerRepository = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)

        let partnerId = household.members.first { $0 != currentUser.id } ?? ""
        if !partnerId.isEmpty {
            Task { [weak self] in
                let partner = await UserRepository().getUserSuspend(partnerId)
                if let partner, !partner.name.isEmpty {
                    await MainActor.run { self?.partnerName = partner.name }
                }
            }
        }
    }

    /// Deletes all shared transactions + my personal transactions + settlements.
    func resetAllTransactions(onSuccess: @escaping () -> Void) {
        guard !isResetting else { return }
        isResetting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ledgerRepository.resetAllTransactions()
                await MainActor.run {
                    self.isResetting = false
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isResetting = false
                }
            }
        }
    }

    /// Removes self from the household and clears my householdId. On failure Android
    /// falls back to signing out completely — same behavior preserved.
    func disconnect(onDisconnected: @escaping () -> Void) {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        Task { [weak self] in
            guard let self else { return }
            let db = Firestore.firestore()
            do {
                let updatedMembers = self.household.members.filter { $0 != self.currentUser.id }
                try await db.collection("households").document(self.household.id)
                    .updateData(["members": updatedMembers])

                var updatedUser = self.currentUser
                updatedUser.householdId = nil
                updatedUser.connectedAt = nil
                try await db.collection("users").document(self.currentUser.id).setData(from: updatedUser)

                await MainActor.run {
                    self.isDisconnecting = false
                    onDisconnected()
                }
            } catch {
                // If it fails, log out completely as a fallback (same as Android).
                await MainActor.run {
                    self.authRepository.signOut()
                    self.isDisconnecting = false
                    onDisconnected()
                }
            }
        }
    }
}
