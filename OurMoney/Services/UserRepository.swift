import Foundation
import FirebaseFirestore

/// Mirror of `data/UserRepository.kt`.
final class UserRepository {
    private let db = Firestore.firestore()

    func getUserSuspend(_ userId: String) async -> User? {
        let trimmed = userId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try await db.collection("users").document(trimmed).getDocument().data(as: User.self)
        } catch {
            return nil
        }
    }

    func listenUser(_ userId: String, onChange: @escaping (User?) -> Void) -> ListenerRegistration? {
        let trimmed = userId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return db.collection("users").document(trimmed).addSnapshotListener { snapshot, error in
            guard error == nil, let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            onChange(try? snapshot.data(as: User.self))
        }
    }
}
