import SwiftUI

/// Mirror of `ui/settings/SettingsScreen.kt`.
struct SettingsView: View {
    let user: User
    let household: Household

    @EnvironmentObject private var authRepository: AuthRepository
    @StateObject private var viewModel: SettingsViewModel
    @State private var partnerName = "Friend"
    @State private var showResetConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showResetSuccess = false
    @State private var copied = false

    init(user: User, household: Household) {
        self.user = user
        self.household = household
        let authRepo = AuthRepositoryHolder.shared.repository
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            currentUser: user, household: household, authRepository: authRepo))
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name", value: user.name)
                LabeledContent("Email", value: user.email.isEmpty ? "—" : user.email)
            }

            Section("Connection") {
                LabeledContent("Connected with", value: partnerName)
                HStack {
                    LabeledContent("Code", value: household.code)
                    Button {
                        UIPasteboard.general.string = household.code
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                Button {
                    showResetConfirm = true
                } label: {
                    Label("Reset all transactions", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(Theme.danger)
                }
                .disabled(viewModel.isResetting)

                Button {
                    showDisconnectConfirm = true
                } label: {
                    Label("Disconnect from \(partnerName)", systemImage: "link.badge.plus")
                        .foregroundStyle(Theme.danger)
                }
                .disabled(viewModel.isDisconnecting)

                Button {
                    showSignOutConfirm = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(Theme.danger)
                }
            }

            if let error = viewModel.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let partnerId = household.members.first { $0 != user.id } ?? ""
            if !partnerId.isEmpty {
                Task {
                    if let partner = await UserRepository().getUserSuspend(partnerId) {
                        partnerName = partner.name.isEmpty ? "Friend" : partner.name
                    }
                }
            }
        }
        .confirmationDialog("Reset ALL transactions?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) {
                viewModel.resetAllTransactions {
                    showResetSuccess = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all shared transactions, your personal transactions and all settlements. Goals and budgets are kept. This cannot be undone.")
        }
        .confirmationDialog("Disconnect?",
                            isPresented: $showDisconnectConfirm,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                viewModel.disconnect { }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will leave the connection and return to the pairing screen.")
        }
        .confirmationDialog("Sign out?",
                            isPresented: $showSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                authRepository.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Done", isPresented: $showResetSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All transactions and settlements were deleted.")
        }
    }
}

/// Bridge so views can reach the shared AuthRepository instance created at app start.
final class AuthRepositoryHolder {
    static let shared = AuthRepositoryHolder()
    var repository: AuthRepository!
}
