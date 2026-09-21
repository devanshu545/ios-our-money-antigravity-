import SwiftUI

/// Mirror of the `OurMoneyApp` composable in MainActivity.kt.
struct RootView: View {
    @EnvironmentObject private var authRepository: AuthRepository
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash || authRepository.authState == .loading {
                SplashView()
            } else {
                switch authRepository.authState {
                case .idle:
                    GoogleSignInScreen()
                case .requiresName(let uid):
                    NameInputScreen(uid: uid)
                case .requiresPairing(let user, let household, let error):
                    PairingScreen(user: user, household: household, error: error)
                case .authenticated(let user, let household):
                    MainTabView(user: user, household: household)
                case .error(let message):
                    Text("Error: \(message)")
                        .foregroundColor(Theme.danger)
                        .padding()
                case .loading:
                    SplashView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authRepository.authState)
        .task {
            // Same 2-second splash as Android.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSplash = false
        }
    }
}

/// Animated splash (port of ui/components/SplashScreen.kt).
struct SplashView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.tealContainer.opacity(0.8), OMColor.background(.dark)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            Image(systemName: "wallet.pass.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundStyle(Theme.teal)
                .scaleEffect(animate ? 1.4 : 0.6)
                .opacity(animate ? 1 : 0)
                .animation(.spring(response: 0.9, dampingFraction: 0.45).repeatForever(autoreverses: false), value: animate)
        }
        .onAppear { animate = true }
    }
}
