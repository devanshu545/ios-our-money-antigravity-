import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import GoogleSignIn
import Combine

/// Mirror of `auth/AuthRepository.kt`: Google Sign-In into Firebase, user document
/// listener, household listener and pairing lifecycle — identical state machine.
final class AuthRepository: ObservableObject {
    @Published private(set) var authState: AuthState = .idle

    private var auth: Auth { Auth.auth() }
    private var db: Firestore { Firestore.firestore() }
    private var householdListener: ListenerRegistration?
    private var userListener: ListenerRegistration?

    init() {
        auth.addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            if let user {
                self.checkCurrentUser(uid: user.uid)
            } else {
                self.userListener?.remove(); self.userListener = nil
                self.householdListener?.remove(); self.householdListener = nil
                self.authState = .idle
            }
        }
    }

    /// Signs in to Firebase using the ID token from the native Google Sign-In sheet.
    /// The same Google account resolves to the same Firebase uid as on Android.
    func signInWithGoogle(idToken: String, accessToken: String) {
        authState = .loading
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        auth.signIn(with: credential) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.authState = .error(message: error.localizedDescription)
            }
            // Success transitions are driven by addStateDidChangeListener -> checkCurrentUser.
        }
    }

    private func checkCurrentUser(uid: String) {
        authState = .loading
        userListener?.remove()
        userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.authState = .error(message: error.localizedDescription)
                return
            }
            guard let snapshot else { return }
            if snapshot.exists, var user = try? snapshot.data(as: User.self) {
                user.id = uid
                if (user.householdId ?? "").isEmpty {
                    self.householdListener?.remove()
                    self.householdListener = nil
                    self.authState = .requiresPairing(user: user, household: nil, error: nil)
                } else {
                    self.listenToHousehold(user)
                }
            } else {
                self.authState = .requiresName(uid: uid)
            }
        }
    }

    private func listenToHousehold(_ user: User) {
        householdListener?.remove()
        guard let householdId = user.householdId else { return }
        householdListener = db.collection("households").document(householdId).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.authState = .error(message: error.localizedDescription)
                return
            }
            guard let snapshot else { return }
            if snapshot.exists, var household = try? snapshot.data(as: Household.self) {
                household.id = householdId
                if !household.members.contains(user.id) {
                    // We are no longer in this household, clear state
                    let uid = user.id
                    Task { try? await Firestore.firestore().collection("users").document(uid)
                        .setData(["householdId": NSNull()], merge: true) }
                    self.authState = .requiresPairing(user: user, household: nil, error: nil)
                } else if household.members.count < 2 {
                    self.authState = .requiresPairing(user: user, household: household, error: nil)
                } else {
                    self.authState = .authenticated(user: user, household: household)
                }
            } else {
                // Household doesn't exist anymore, clear it from user
                let uid = user.id
                Task { try? await Firestore.firestore().collection("users").document(uid)
                    .setData(["householdId": NSNull()], merge: true) }
                self.authState = .requiresPairing(user: user, household: nil, error: nil)
            }
        }
    }

    func saveName(name: String) async {
        guard let current = auth.currentUser else { return }
        await MainActor.run { authState = .loading }
        let user = User(id: current.uid, name: name, email: current.email ?? "")
        do {
            let ref = db.collection("users").document(current.uid)
            try await ref.setData(from: user)
        } catch {
            await MainActor.run { authState = .error(message: error.localizedDescription) }
        }
    }

    /// Creates a household with a random 6-digit code and joins it (same flow as Android).
    func createHousehold(user: User) async {
        await MainActor.run { authState = .loading }
        let code = String(Int.random(in: 100000...999999))
        let householdId = UUID().uuidString
        let household = Household(id: householdId, code: code, members: [user.id])
        do {
            let hRef = db.collection("households").document(householdId)
            try await hRef.setData(from: household)

            var updatedUser = user
            updatedUser.householdId = household.id
            updatedUser.connectedAt = Int64(Date().timeIntervalSince1970 * 1000)
            let uRef = db.collection("users").document(user.id)
            try await uRef.setData(from: updatedUser)
            // Listener will transition to authenticated / pairing-with-household.
        } catch {
            await MainActor.run {
                authState = .requiresPairing(user: user, household: nil,
                                             error: "Unable to connect. Check your internet connection and try again.")
            }
        }
    }

    func joinHousehold(user: User, code: String) async {
        await MainActor.run { authState = .loading }
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        do {
            let result = try await db.collection("households")
                .whereField("code", isEqualTo: trimmedCode).getDocuments()
            guard let doc = result.documents.first else {
                await MainActor.run {
                    authState = .requiresPairing(user: user, household: nil, error: "Invalid connection code.")
                }
                return
            }
            guard var household = try? doc.data(as: Household.self) else { return }
            household.id = doc.documentID

            if household.members.count >= 2 && !household.members.contains(user.id) {
                await MainActor.run {
                    authState = .requiresPairing(user: user, household: nil,
                                                 error: "This connection already has two members.")
                }
                return
            }

            // Same ordering behavior as Android: append then distinct (keeps existing order).
            var updatedMembers = household.members
            if !updatedMembers.contains(user.id) { updatedMembers.append(user.id) }
            try await doc.reference.updateData(["members": updatedMembers])

            var updatedUser = user
            updatedUser.householdId = doc.documentID
            updatedUser.connectedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try await db.collection("users").document(user.id).setData(from: updatedUser)
        } catch {
            await MainActor.run {
                authState = .requiresPairing(user: user, household: nil,
                                             error: "Unable to connect. Check your internet connection and try again.")
            }
        }
    }

    /// Mirrors Android `cancelPairing`: clear my householdId and delete the old household document.
    func cancelPairing(user: User) async {
        await MainActor.run { authState = .loading }
        do {
            var updatedUser = user
            updatedUser.householdId = nil
            updatedUser.connectedAt = nil
            try await db.collection("users").document(user.id).setData(from: updatedUser)

            if let oldHouseholdId = user.householdId, !oldHouseholdId.isEmpty {
                try await db.collection("households").document(oldHouseholdId).delete()
            }
        } catch {
            await MainActor.run {
                authState = .requiresPairing(user: user, household: nil, error: "Failed to cancel connection.")
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? auth.signOut()
        userListener?.remove(); userListener = nil
        householdListener?.remove(); householdListener = nil
        authState = .idle
    }

    func setError(message: String) {
        authState = .error(message: message)
    }
}
