import SwiftUI

/// Mirror of `ui/expense/AddExpenseScreen.kt`, adapted to native iOS form patterns.
/// Functional parity notes (from the Android source):
/// - Payment methods are exactly UPI and Cash (Android radio buttons).
/// - Split is always EQUAL; splits are auto-computed: personal → [(me, full)],
///   shared → [(me, half), (other, amountPaise - half)] with integer division.
/// - Date AND time are editable (Android date picker → time picker chain).
struct AddExpenseView: View {
    let user: User
    let household: Household
    let transactionId: String?
    let onDone: () -> Void

    @StateObject private var viewModel: AddExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amountStr = ""
    @State private var category = ""
    @State private var isPersonal = false
    @State private var paidByMe = true
    @State private var paymentMethod = "UPI"
    @State private var notes = ""
    @State private var expenseDate = Date()
    @State private var initialsPopulated = false

    @State private var showDeleteConfirm = false
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    init(user: User, household: Household, transactionId: String?, onDone: @escaping () -> Void) {
        self.user = user
        self.household = household
        self.transactionId = transactionId
        self.onDone = onDone
        _viewModel = StateObject(wrappedValue: AddExpenseViewModel(currentUser: user, household: household))
    }

    private var allCategories: [String] {
        let custom = viewModel.customCategories.map(\.name)
        return Array(Set(AddExpenseViewModel.standardCategories + custom)).sorted()
    }

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    Text("₹").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("0", text: $amountStr)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.bold))
                }
            }

            Section("Details") {
                Picker("Category", selection: $category) {
                    ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    showAddCategory = true
                } label: {
                    Label("Add Custom Category…", systemImage: "plus.circle")
                }
                if let customCat = viewModel.customCategories.first(where: { $0.name == category }) {
                    Button(role: .destructive) {
                        viewModel.deleteCustomCategory(categoryId: customCat.id)
                        category = ""
                    } label: {
                        Label("Delete \"\(customCat.name)\"", systemImage: "trash")
                    }
                }

                Toggle(isOn: $isPersonal) {
                    Text("Personal (only you can see this)")
                }

                if !isPersonal && !viewModel.otherUserId.isEmpty {
                    Picker("Paid By", selection: $paidByMe) {
                        Text("You").tag(true)
                        Text(viewModel.partnerName).tag(false)
                    }
                }

                Picker("Payment Method", selection: $paymentMethod) {
                    Text("UPI").tag("UPI")
                    Text("Cash").tag("Cash")
                }
                .pickerStyle(.segmented)

                DatePicker("Date & Time", selection: $expenseDate,
                           displayedComponents: [.date, .hourAndMinute])

                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(1...3)
            }

            if let error = viewModel.error {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                            Text("Saving…")
                        } else {
                            Text("Save")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isSaving)
            }

            if transactionId != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Expense", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(transactionId == nil ? "Add Expense" : "Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onDone() }
                    .disabled(viewModel.isSaving)
            }
        }
        .onAppear {
            if transactionId != nil {
                viewModel.loadTransaction(transactionId: transactionId!)
            } else {
                viewModel.setModeCreate()
                populateInitials()
            }
        }
        .onReceive(viewModel.$initialDataLoaded) { ready in
            if ready, transactionId != nil, !initialsPopulated {
                initialsPopulated = true
                populateInitials()
            }
        }
        .alert("Add Custom Category", isPresented: $showAddCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Add") {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    viewModel.addCustomCategory(name: trimmed)
                    category = trimmed
                }
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
        .alert("Delete expense?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = transactionId {
                    viewModel.ledgerRepository.deleteTransaction(transactionId: id)
                }
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the expense for both you and your friend.")
        }
        .preferredColorScheme(.dark)
    }

    private func populateInitials() {
        amountStr = viewModel.initialAmountStr
        category = viewModel.initialCategory
        isPersonal = viewModel.initialIsPersonal
        paidByMe = viewModel.initialPaidByMe
        paymentMethod = viewModel.initialPaymentMethod
        notes = viewModel.initialNotes
        expenseDate = Date(timeIntervalSince1970: TimeInterval(viewModel.initialDateMillis) / 1000)
        initialsPopulated = true
    }

    private func save() {
        guard let paise = Formatters.parseRupeesToPaise(amountStr), paise > 0 else {
            viewModel.error = "Please enter a valid amount and category"
            return
        }
        guard !category.trimmingCharacters(in: .whitespaces).isEmpty else {
            viewModel.error = "Please enter a valid amount and category"
            return
        }

        // Same split computation as Android AddExpenseScreen.
        let splits: [SplitAmount]
        if isPersonal || viewModel.otherUserId.isEmpty {
            splits = [SplitAmount(userId: user.id, amountPaise: paise)]
        } else {
            let half = paise / 2
            let otherHalf = paise - half
            splits = [SplitAmount(userId: user.id, amountPaise: half),
                      SplitAmount(userId: viewModel.otherUserId, amountPaise: otherHalf)]
        }

        viewModel.saveExpense(
            amountPaise: paise,
            category: category,
            isPersonal: isPersonal,
            paidByCurrentUser: paidByMe,
            splitMethod: .equal,
            splits: splits,
            notes: notes,
            paymentMethod: paymentMethod,
            dateMillis: Int64(expenseDate.timeIntervalSince1970 * 1000)
        ) {
            onDone()
        }
    }
}
