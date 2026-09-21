import SwiftUI

/// Mirror of `ui/dashboard/DashboardScreen.kt`, adapted to native iOS navigation.
struct DashboardView: View {
    let user: User
    let household: Household
    let onAddExpense: () -> Void
    let onEditExpense: (String) -> Void
    let onSettleUp: () -> Void
    let onSettings: () -> Void

    @StateObject private var viewModel: DashboardViewModel
    @State private var searchQuery = ""
    @State private var deleteTarget: Transaction?

    init(user: User, household: Household,
         onAddExpense: @escaping () -> Void,
         onEditExpense: @escaping (String) -> Void,
         onSettleUp: @escaping () -> Void,
         onSettings: @escaping () -> Void) {
        self.user = user
        self.household = household
        self.onAddExpense = onAddExpense
        self.onEditExpense = onEditExpense
        self.onSettleUp = onSettleUp
        self.onSettings = onSettings
        _viewModel = StateObject(wrappedValue: DashboardViewModel(currentUser: user, household: household))
    }

    private var partnerName: String {
        viewModel.state.partnerUser?.name ?? "Friend"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        balanceCard

                        TextField("Search transactions…", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 4)

                        recentTransactions
                    }
                    .padding()
                }
            }
            .navigationTitle("OurMoney")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("OurMoney").font(.headline)
                        Text("Connected with \(partnerName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Button(action: onSettleUp) {
                            Text("Settle")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.thinMaterial, in: Capsule())
                        }
                        Button(action: onAddExpense) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Theme.tealDeep, in: Circle())
                                .shadow(radius: 6, y: 3)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
                }
            }
            .refreshable {
                // Firestore listeners deliver updates in real time; pull-to-refresh
                // gives the user explicit re-sync affordance.
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Delete transaction?",
               isPresented: Binding(get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    viewModel.deleteTransaction(transactionId: target.id)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This will remove the transaction for both you and your friend.")
        }
    }

    private var balanceCard: some View {
        let balance = viewModel.state.balance
        return VStack(spacing: 10) {
            if balance.netBalancePaise > 0 {
                Text("\(partnerName) owes you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Formatters.formatRupees(balance.amountOwedToMePaise))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.success)
            } else if balance.netBalancePaise < 0 {
                Text("You owe \(partnerName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Formatters.formatRupees(balance.amountIOwePaise))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.danger)
            } else {
                Text("All settled up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("₹0")
                    .font(.system(size: 40, weight: .bold))
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You paid").font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.formatRupees(balance.totalSharedPaidByMePaise))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(partnerName) paid").font(.caption).foregroundStyle(.secondary)
                    Text(Formatters.formatRupees(balance.totalSharedPaidByPartnerPaise))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var recentTransactions: some View {
        let filtered = filteredTransactions
        return Group {
            if viewModel.state.isLoading {
                ProgressView().padding(.vertical, 40)
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(searchQuery.isEmpty ? "No transactions yet" : "No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { tx in
                        TransactionRow(
                            transaction: tx,
                            currentUserId: user.id,
                            partnerName: partnerName,
                            onDelete: { deleteTarget = tx },
                            onEdit: { onEditExpense(tx.id) }
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    /// Search across category + notes (same fields Android matches on the dashboard);
    /// without a query the dashboard shows recent transactions first.
    private var filteredTransactions: [Transaction] {
        let all = viewModel.state.transactions
        guard !searchQuery.isEmpty else { return Array(all.prefix(20)) }
        let q = searchQuery.lowercased()
        return all.filter {
            $0.category.lowercased().contains(q) || $0.notes.lowercased().contains(q)
        }
    }
}
