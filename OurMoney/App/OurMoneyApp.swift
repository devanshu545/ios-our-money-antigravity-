import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct OurMoneyApp: App {
    @StateObject private var authRepository = AuthRepository()

    init() {
        // Configure Firebase from GoogleService-Info.plist (same project as Android).
        FirebaseApp.configure()
        GoogleSignInService.shared.configure()
        GoogleSignInService.shared.attach(repository: authRepository)
        // Bridge so SettingsView can reach the same AuthRepository instance.
        AuthRepositoryHolder.shared.repository = authRepository
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authRepository)
                .onOpenURL { url in
                    _ = GoogleSignInService.shared.handle(url: url)
                }
        }
    }
}
