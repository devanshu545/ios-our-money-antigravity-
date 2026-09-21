import SwiftUI

// MARK: - Google Sign-In (Idle)

struct GoogleSignInScreen: View {
    @EnvironmentObject private var authRepository: AuthRepository

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wallet.pass.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .foregroundStyle(Theme.teal)
            Text("OurMoney")
                .font(.system(size: 34, weight: .bold))
            Text("Shared money, made simple.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                GoogleSignInService.shared.signIn()
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text("Continue with Google")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.tealDeep)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Name Input (RequiresName)

struct NameInputScreen: View {
    let uid: String
    @EnvironmentObject private var authRepository: AuthRepository
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .foregroundStyle(Theme.teal)
            Text("What should we call you?")
                .font(.title2.weight(.semibold))
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 32)
                .onSubmit { save() }
            Button {
                save()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.tealDeep)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 32)
            Spacer()
        }
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { await authRepository.saveName(name: trimmed) }
    }
}

// MARK: - Pairing (RequiresPairing)

struct PairingScreen: View {
    let user: User
    let household: Household?
    let error: String?

    @EnvironmentObject private var authRepository: AuthRepository
    @State private var joinCode = ""
    @State private var showCancelConfirm = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "link.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Theme.teal)
                        .padding(.top, 32)

                    Text("Connect with a friend")
                        .font(.title2.weight(.semibold))
                    Text("Share one private code between you and one friend to track money together.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let error, !error.isEmpty {
                        Text(error)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 24)
                    }

                    // My code (if a household exists — same as Android)
                    if let household {
                        VStack(spacing: 8) {
                            Text("Your connection code")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(household.code)
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .kerning(6)
                                .foregroundStyle(Theme.teal)
                            Button {
                                UIPasteboard.general.string = household.code
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 16)
                    }

                    // Create
                    if household == nil {
                        Button {
                            Task { await authRepository.createHousehold(user: user) }
                        } label: {
                            Text("Create connection")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tealDeep)
                        .padding(.horizontal, 24)
                    }

                    Divider().padding(.horizontal, 24)

                    // Join
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Have a code?")
                            .font(.headline)
                        TextField("6-digit code", text: $joinCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await authRepository.joinHousehold(user: user, code: joinCode) }
                        } label: {
                            Text("Join connection")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tealDeep)
                        .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }

            // Cancel / leave connection
            if household != nil {
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Text("Cancel connection")
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Cancel this connection?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel connection", role: .destructive) {
                Task { await authRepository.cancelPairing(user: user) }
            }
        } message: {
            Text("The connection code will stop working and shared data for this connection will be removed.")
        }
    }
}
