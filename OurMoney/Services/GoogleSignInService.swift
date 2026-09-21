import Foundation
import GoogleSignIn
import FirebaseCore
import UIKit

/// Presents the native Google Sign-In sheet and forwards the resulting ID token to
/// `AuthRepository` (equivalent of Android's Credential Manager flow).
final class GoogleSignInService {
    static let shared = GoogleSignInService()

    private var authRepository: AuthRepository?

    /// Must be called once at launch, after FirebaseApp.configure().
    func configure() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }

    func attach(repository: AuthRepository) {
        self.authRepository = repository
    }

    @MainActor
    func signIn() {
        guard let rootVC = UIApplication.shared.topViewController() else { return }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            guard let self else { return }
            if let error {
                // User cancelled or Google failed; keep current state (do not fake sign-in).
                if (error as NSError).code != GIDSignInErrorCode.canceled.rawValue {
                    self.authRepository?.setError(message: error.localizedDescription)
                }
                return
            }
            guard let idToken = result?.user.idToken?.tokenString else { return }
            self.authRepository?.signInWithGoogle(idToken: idToken)
        }
    }

    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
