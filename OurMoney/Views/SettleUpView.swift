import SwiftUI

/// Mirror of `ui/settlement/SettleUpScreen.kt`.
struct SettleUpView: View {
    let user: User
    let household: Household
    let settlementId: String?
    let onDone: () -> Void

    @StateObject private var viewModel: SettleUpViewModel
    @State private var amountStr = ""
    @State private var paidByMe = true
    @State private var paymentMethod = "UPI"
    @State private var notes = ""
    @State private var settleDate = Date()
    @State private var loaded = false
    @State private var initialsPopulated = false
    @State private var showDeleteConfirm = false

    init(user: User, household: Household, settlementId: String?, onDone: @escaping () -> Void) {
        self.user = user
        self.household = household
        self.settlementId = settlementId
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: SettleUpViewModel(currentUser: user, household: household))
    }

    var body: some View {
        Form {
            balanceSection
            formSection
            if let error = viewModel.error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            }
            saveSection
            if settlementId != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Settlement", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            historySection
        }
        .navigationTitle(settlementId == nil ? "Settle Up" : "Edit Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onDone() }
                    .disabled(viewModel.isSaving)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let settlementId {
                viewModel.loadSettlement(settlementId: settlementId)
            } else {
                viewModel.setModeCreate()
            }
        }
        .onReceive(viewModel.$initialDataLoaded) { ready in
            guard ready, settlementId != nil, !initialsPopulated else { return }
            initialsPopulated = true
            populateInitials()
        }
        .alert("Delete settlement?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = settlementId {
                    viewModel.deleteSettlement(settlementId: id) {
                        onDone()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting a settlement will adjust both balances.")
        }
        .preferredColorScheme(.dark)
    }

    private var balanceSection: some View {
        let balance = viewModel.balance
        return Section("Current balance") {
            if balance.netBalancePaise > 0 {
                Text("\(viewModel.partnerName) owes you \(Formatters.formatRupees(balance.amountOwedToMePaise))")
                    .foregroundStyle(Theme.success)
            } else if balance.netBalancePaise < 0 {
                Text("You owe \(viewModel.partnerName) \(Formatters.formatRupees(balance.amountIOwePaise))")
                    .foregroundStyle(Theme.danger)
            } else {
                Text("All settled up").foregroundStyle(.secondary)
            }
        }
    }

    private var formSection: some View {
        Section("Settlement") {
            HStack {
                Text("₹").foregroundStyle(.secondary)
                TextField("0", text: $amountStr)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.bold))
            }
            Picker("Paid by", selection: $paidByMe) {
                Text("Me").tag(true)
                Text(viewModel.partnerName).tag(false)
            }
            Picker("Method", selection: $paymentMethod) {
                ForEach(["UPI", "Cash", "Card", "Net Banking", "Other"], id: \.self) { Text($0).tag($0) }
            }
            DatePicker("Date", selection: $settleDate, displayedComponents: .date)
            TextField("Notes", text: $notes)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                save()
            } label: {
                HStack {
                    if viewModel.isSaving { ProgressView().tint(.white) }
                    Text(settlementId == nil ? "Record Settlement" : "Save Changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isSaving)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.settlements.isEmpty {
            Section("Past settlements") {
                ForEach(viewModel.settlements.prefix(10)) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.paidBy == user.id ? "You paid \(viewModel.partnerName)" : "\(viewModel.partnerName) paid you")
                                .font(.subheadline.weight(.semibold))
                            Text(Formatters.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(s.dateMillis) / 1000)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formatters.formatRupees(s.amountPaise))
                            .font(.subheadline.weight(.bold))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteTarget = s } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func populateInitials() {
        amountStr = viewModel.initialAmountStr
        paidByMe = viewModel.initialPaidByMe
        paymentMethod = viewModel.initialPaymentMethod
        notes = viewModel.initialNotes
        settleDate = Date(timeIntervalSince1970: TimeInterval(viewModel.initialDateMillis) / 1000)
    }

    private func save() {
        guard let paise = Formatters.parseRupeesToPaise(amountStr), paise > 0 else {
            viewModel.error = "Amount must be greater than 0"
            return
        }
        viewModel.saveSettlement(
            amountPaise: paise,
            paidByCurrentUser: paidByMe,
            paymentMethod: paymentMethod,
            notes: notes,
            dateMillis: Int64(settleDate.timeIntervalSince1970 * 1000)
        ) {
            onDone()
        }
    }
}
