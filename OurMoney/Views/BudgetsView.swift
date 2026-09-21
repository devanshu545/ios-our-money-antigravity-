import SwiftUI

/// Mirror of `ui/budgets/BudgetsScreen.kt`, adapted to native iOS layout.
struct BudgetsView: View {
    let user: User
    let household: Household

    @StateObject private var viewModel: BudgetsViewModel
    @State private var showAddBudget = false
    @State private var editBudget: Budget?
    @State private var deleteBudgetTarget: Budget?
    @State private var expandedCategoryId: String?
    @State private var showAddCategory = false
    @State private var newCategoryName = ""

    init(user: User, household: Household) {
        self.user = user
        self.household = household
        _viewModel = StateObject(wrappedValue: BudgetsViewModel(currentUser: user, household: household))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        monthSelector
                        scopeSelector
                        if let state = viewModel.budgetState {
                            summaryCard(state)
                            healthChip(state.healthStatus)
                            WeeklyBarChart(data: state.weeklyChartData)
                                .padding(.vertical, 8)
                            insightCards(state.insights)
                            categoryList(state)
                        } else {
                            ProgressView().padding(.vertical, 60)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddBudget = true
                        } label: {
                            Label("Add budget", systemImage: "plus")
                        }
                        Button {
                            showAddCategory = true
                        } label: {
                            Label("Manage categories", systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddBudget) {
                NavigationStack { budgetForm(existing: nil) }
            }
            .sheet(isPresented: Binding(get: { editBudget != nil },
                                        set: { if !$0 { editBudget = nil } })) {
                NavigationStack { budgetForm(existing: editBudget) }
                    .onAppear { }
            }
            .alert("Add category", isPresented: $showAddCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Add") {
                    viewModel.addCustomCategory(name: newCategoryName)
                    newCategoryName = ""
                }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .confirmationDialog("Delete budget?",
                                isPresented: Binding(get: { deleteBudgetTarget != nil },
                                                     set: { if !$0 { deleteBudgetTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let target = deleteBudgetTarget {
                        viewModel.deleteBudget(budgetId: target.id)
                    }
                    deleteBudgetTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteBudgetTarget = nil }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                viewModel.previousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            Spacer()
            Text(Formatters.monthNameFormatter.string(from: viewModel.selectedMonth))
                .font(.headline)
            Spacer()
            Button {
                viewModel.nextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private var scopeSelector: some View {
        Picker("Scope", selection: $viewModel.selectedScope) {
            ForEach(BudgetScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private func summaryCard(_ state: ComprehensiveBudgetState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total budget")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Formatters.formatRupees(state.totalBudgetPaise))
                .font(.system(size: 36, weight: .bold))

            ProgressView(value: min(1.0, Double(state.totalSpentPaise) / Double(max(1, state.totalBudgetPaise))))
                .tint(state.totalSpentPaise > state.totalBudgetPaise ? Theme.danger : Theme.teal)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent").font(.caption2).foregroundStyle(.secondary)
                    Text(Formatters.formatRupees(state.totalSpentPaise)).font(.subheadline.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Safe daily").font(.caption2).foregroundStyle(.secondary)
                    Text(Formatters.formatRupees(state.safeDailyLimitPaise)).font(.subheadline.weight(.semibold))
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent today").font(.caption2).foregroundStyle(.secondary)
                    Text(Formatters.formatRupees(state.spentTodayPaise)).font(.subheadline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.daysRemaining) days left").font(.caption2).foregroundStyle(.secondary)
                    Text("Projected: \(Formatters.formatRupees(state.expectedMonthEndPaise))").font(.caption)
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func healthChip(_ status: BudgetHealth) -> some View {
        let color: Color = {
            switch status {
            case .onTrack: return Theme.success
            case .watch: return Theme.brandBlue
            case .atRisk: return Theme.warning
            case .overBudget: return Theme.danger
            }
        }()
        return Text(status.rawValue)
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color, in: Capsule())
    }

    private func insightCards(_ insights: [String]) -> some View {
        Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Insights")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.caption2)
                                .foregroundStyle(Theme.teal)
                                .padding(.top, 2)
                            Text(insight)
                                .font(.footnote)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func categoryList(_ state: ComprehensiveBudgetState) -> some View {
        Group {
            if state.categories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No budgets for \(state.monthName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showAddBudget = true
                    } label: {
                        Text("Create a budget")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(state.categories) { stat in
                        categoryCard(stat)
                    }
                }
            }
        }
    }

    private func categoryCard(_ stat: CategoryStat) -> some View {
        let pct = Double(stat.spentPaise) / Double(max(1, stat.budget.limitAmountPaise))
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { expandedCategoryId = expandedCategoryId == stat.id ? nil : stat.id }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.budget.category)
                            .font(.subheadline.weight(.semibold))
                        Text(stat.budget.personal ? "Personal" : "Shared")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Formatters.formatRupees(stat.spentPaise)) / \(Formatters.formatRupees(stat.budget.limitAmountPaise))")
                            .font(.footnote.weight(.semibold))
                        Text("\(Int(pct * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            ProgressView(value: min(1.0, pct))
                .tint(pct > 1 ? Theme.danger : pct > 0.85 ? Theme.warning : Theme.teal)

            if expandedCategoryId == stat.id {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(stat.totalTransactions) transactions")
                        Spacer()
                        Text("Largest: \(Formatters.formatRupees(stat.largestTransaction))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(stat.transactions.prefix(5)) { tx in
                        HStack {
                            Text(Formatters.shortDayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tx.notes.isEmpty ? tx.category : tx.notes)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(Formatters.formatRupees(tx.amountPaise))
                                .font(.caption.weight(.semibold))
                        }
                    }

                    HStack {
                        Button {
                            editBudget = stat.budget
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            deleteBudgetTarget = stat.budget
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func budgetForm(existing: Budget?) -> some View {
        BudgetFormView(viewModel: viewModel, existing: existing) { dismissBudgetSheet() }
            .preferredColorScheme(.dark)
    }

    private func dismissBudgetSheet() {
        showAddBudget = false
        editBudget = nil
    }
}

/// Add/edit budget form.
private struct BudgetFormView: View {
    @ObservedObject var viewModel: BudgetsViewModel
    let existing: Budget?
    let onDone: () -> Void

    @State private var category = ""
    @State private var amountStr = ""
    @State private var isPersonal = false

    var body: some View {
        Form {
            Section("Budget") {
                Picker("Category", selection: $category) {
                    let all = Array(Set(AddExpenseViewModel.standardCategories +
                                        viewModel.customCategories.map(\.name))).sorted()
                    ForEach(all, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("₹")
                    TextField("Monthly limit", text: $amountStr)
                        .keyboardType(.decimalPad)
                }
                Picker("Scope", selection: $isPersonal) {
                    Text("Shared").tag(false)
                    Text("Personal").tag(true)
                }
            }
            Section {
                Button {
                    save()
                } label: {
                    Text(existing == nil ? "Add Budget" : "Save Changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(existing == nil ? "Add Budget" : "Edit Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onDone() }
            }
        }
        .onAppear {
            if let existing {
                category = existing.category
                amountStr = Formatters.plainAmountString(existing.limitAmountPaise)
                isPersonal = existing.personal
            } else if category.isEmpty {
                category = AddExpenseViewModel.standardCategories.first ?? ""
            }
        }
    }

    private func save() {
        guard let paise = Formatters.parseRupeesToPaise(amountStr), paise > 0 else { return }
        viewModel.saveBudget(existing: existing,
                             category: category,
                             limitAmountPaise: paise,
                             isPersonal: isPersonal) {
            onDone()
        }
    }
}
