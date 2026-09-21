import SwiftUI

/// Mirror of `ui/history/HistoryScreen.kt`: combined feed, search, filters, PDF export.
struct HistoryView: View {
    let user: User
    let household: Household
    let onEditExpense: (String) -> Void
    let onEditSettlement: (String) -> Void

    @StateObject private var viewModel: HistoryViewModel
    @State private var showReportDialog = false
    @State private var reportScope: BudgetScope = .all
    @State private var reportType = "Monthly"
    @State private var deleteTarget: HistoryViewModel.HistoryRow?
    @State private var sharingUrl: URL?
    @State private var filterStart: Date?
    @State private var filterEnd: Date?
    @State private var showStartDate = false
    @State private var showEndDate = false

    init(user: User, household: Household,
         onEditExpense: @escaping (String) -> Void,
         onEditSettlement: @escaping (String) -> Void) {
        self.user = user
        self.household = household
        self.onEditExpense = onEditExpense
        self.onEditSettlement = onEditSettlement
        _viewModel = StateObject(wrappedValue: HistoryViewModel(currentUser: user, household: household))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                rowsList
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReportDialog = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.rows.isEmpty)
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search category, notes, amount, date")
            .sheet(isPresented: $showReportDialog) {
                reportDialog
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: Binding(get: { sharingUrl != nil },
                                        set: { if !$0 { sharingUrl = nil } })) {
                if let url = sharingUrl {
                    ActivityView(url: url)
                }
            }
            .confirmationDialog("Delete this entry?",
                                isPresented: Binding(get: { deleteTarget != nil },
                                                     set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        viewModel.deleteTransaction(transactionId: target.id, isSettlement: target.settlement != nil)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This will be removed for both you and your friend.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private var rowsList: some View {
        VStack(spacing: 0) {
            filterBar
            if viewModel.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.rows) { row in
                        rowView(row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All time") { filterStart = nil; filterEnd = nil }
                Button("Custom range…") { showStartDate = true }
            } label: {
                Label(filterLabel, systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
            }
            if filterStart != nil || filterEnd != nil {
                Button {
                    filterStart = nil
                    filterEnd = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .popover(isPresented: $showStartDate) {
            DatePicker("From", selection: Binding(get: { filterStart ?? Date() },
                                                  set: { filterStart = $0; showStartDate = false; showEndDate = true }),
                       displayedComponents: .date)
                .presentationDetents([.fraction(0.3)])
                .padding()
        }
        .popover(isPresented: $showEndDate) {
            DatePicker("To", selection: Binding(get: { filterEnd ?? Date() },
                                                set: { filterEnd = $0; showEndDate = false }),
                       in: (filterStart ?? .distantPast)...,
                       displayedComponents: .date)
                .presentationDetents([.fraction(0.3)])
                .padding()
        }
    }

    private var filterLabel: String {
        if let s = filterStart, let e = filterEnd {
            return "\(Formatters.shortDayFormatter.string(from: s)) – \(Formatters.shortDayFormatter.string(from: e))"
        }
        return "All time"
    }

    @ViewBuilder
    private func rowView(_ row: HistoryViewModel.HistoryRow) -> some View {
        let inRange = dateFilterMatches(row)
        if inRange {
            if let settlement = row.settlement {
                TransactionRow(
                    transaction: Transaction(
                        id: settlement.id,
                        amountPaise: settlement.amountPaise,
                        category: "Settlement",
                        dateMillis: settlement.dateMillis,
                        paidBy: settlement.paidBy,
                        createdBy: settlement.createdBy,
                        personal: false,
                        notes: settlement.notes,
                        type: .transfer,
                        paymentMethod: settlement.paymentMethod,
                        isPending: settlement.isPending
                    ),
                    currentUserId: user.id,
                    partnerName: viewModel.partnerUser?.name ?? "Friend",
                    isSettlement: true,
                    onDelete: { deleteTarget = row },
                    onEdit: { onEditSettlement(settlement.id) }
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let tx = row.transaction {
                TransactionRow(
                    transaction: tx,
                    currentUserId: user.id,
                    partnerName: viewModel.partnerUser?.name ?? "Friend",
                    onDelete: { deleteTarget = row },
                    onEdit: { onEditExpense(tx.id) }
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func dateFilterMatches(_ row: HistoryViewModel.HistoryRow) -> Bool {
        if let s = filterStart {
            let startMillis = Int64(Calendar.current.startOfDay(for: s).timeIntervalSince1970 * 1000)
            if row.dateMillis < startMillis { return false }
        }
        if let e = filterEnd {
            var endCal = Calendar.current.startOfDay(for: e)
            endCal = endCal.addingTimeInterval(86_399)
            let endMillis = Int64(endCal.timeIntervalSince1970 * 1000)
            if row.dateMillis > endMillis { return false }
        }
        return true
    }

    // MARK: - Report dialog (port of the Android PDF export dialog)

    private var reportDialog: some View {
        VStack(spacing: 18) {
            Text("Export PDF Report")
                .font(.headline)
            Picker("Scope", selection: $reportScope) {
                ForEach(BudgetScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            Picker("Report type", selection: $reportType) {
                Text("Weekly").tag("Weekly")
                Text("Monthly").tag("Monthly")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Button {
                exportPdf()
            } label: {
                Label("Generate & Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.tealDeep)
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 24)
    }

    private func exportPdf() {
        let txs = viewModel.rows.compactMap(\.transaction)
        let allTxs = viewModel.ledgerRepository.transactions
        let budgets = viewModel.budgets
        let (startMillis, endMillis, periodName): (Int64, Int64, String)
        if reportType == "Weekly" {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            startMillis = Int64(start.timeIntervalSince1970 * 1000)
            endMillis = Int64(Date().timeIntervalSince1970 * 1000)
            periodName = "Last 7 days"
        } else {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            startMillis = Int64(start.timeIntervalSince1970 * 1000)
            endMillis = Int64(Date().timeIntervalSince1970 * 1000)
            periodName = "Last 30 days"
        }
        let scoped = txs.filter { tx in
            switch reportScope {
            case .all: return tx.personal ? tx.createdBy == user.id : true
            case .shared: return !tx.personal
            case .personal: return tx.personal && tx.createdBy == user.id
            }
        }
        showReportDialog = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let url = PdfService.generateReport(
                transactions: scoped,
                allScopeTransactions: allTxs,
                budgets: budgets,
                currentUser: user,
                partnerUser: viewModel.partnerUser,
                scopeName: reportScope.rawValue,
                periodName: periodName,
                reportType: reportType,
                startDateMillis: startMillis,
                endDateMillis: endMillis
            ) {
                sharingUrl = url
            }
        }
    }
}

/// UIKit share sheet wrapper.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
