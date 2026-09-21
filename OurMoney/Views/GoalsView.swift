import SwiftUI

/// Mirror of `ui/goals/GoalsScreen.kt`.
struct GoalsView: View {
    let user: User
    let household: Household

    @StateObject private var viewModel: GoalsViewModel
    @State private var showAddDialog = false
    @State private var editGoal: Goal?
    @State private var contributeGoal: Goal?
    @State private var deleteGoal: Goal?

    init(user: User, household: Household) {
        self.user = user
        self.household = household
        _viewModel = StateObject(wrappedValue: GoalsViewModel(currentUser: user, household: household))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                if viewModel.goals.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "target")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No savings goals yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showAddDialog = true
                        } label: {
                            Text("Create a goal")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tealDeep)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.goals) { goal in
                                goalCard(goal)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddDialog) { goalForm(existing: nil) }
            .sheet(isPresented: Binding(get: { editGoal != nil },
                                        set: { if !$0 { editGoal = nil } })) {
                goalForm(existing: editGoal)
            }
            .sheet(isPresented: Binding(get: { contributeGoal != nil },
                                        set: { if !$0 { contributeGoal = nil } })) {
                if let goal = contributeGoal {
                    ContributeSheet(goal: goal) { amountPaise in
                        viewModel.addContribution(goal, amountPaise: amountPaise) { }
                    }
                    .presentationDetents([.fraction(0.35)])
                }
            }
            .confirmationDialog("Delete goal?",
                                isPresented: Binding(get: { deleteGoal != nil },
                                                     set: { if !$0 { deleteGoal = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let goal = deleteGoal {
                        viewModel.deleteGoal(goal)
                    }
                    deleteGoal = nil
                }
                Button("Cancel", role: .cancel) { deleteGoal = nil }
            } message: {
                Text("This goal will be removed for both you and your friend.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private func goalCard(_ goal: Goal) -> some View {
        let pct = Double(goal.currentAmountPaise) / Double(max(1, goal.targetAmountPaise))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.subheadline.weight(.semibold))
                    Text(goal.personal ? "Personal" : "Shared")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.teal)
            }

            ProgressView(value: min(1.0, pct))
                .tint(Theme.teal)

            HStack {
                Text("\(Formatters.formatRupees(goal.currentAmountPaise)) of \(Formatters.formatRupees(goal.targetAmountPaise))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button {
                        contributeGoal = goal
                    } label: {
                        Label("Add contribution", systemImage: "plus.circle")
                    }
                    Button {
                        editGoal = goal
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteGoal = goal
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func goalForm(existing: Goal?) -> some View {
        GoalFormView(viewModel: viewModel, existing: existing) {
            self.editGoal = nil
            self.showAddDialog = false
        }
        .preferredColorScheme(.dark)
    }
}

private struct GoalFormView: View {
    @ObservedObject var viewModel: GoalsViewModel
    let existing: Goal?
    let onDone: () -> Void

    @State private var name = ""
    @State private var targetStr = ""
    @State private var isPersonal = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name (e.g. New laptop)", text: $name)
                    HStack {
                        Text("₹")
                        TextField("Target amount", text: $targetStr)
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
                        Text(existing == nil ? "Add Goal" : "Save Changes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDone() }
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    targetStr = Formatters.plainAmountString(existing.targetAmountPaise)
                    isPersonal = existing.personal
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let paise = Formatters.parseRupeesToPaise(targetStr), paise > 0 else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing {
            viewModel.editGoal(existing, newName: trimmed, newTarget: paise) { onDone() }
        } else {
            viewModel.addGoal(name: trimmed, targetAmountPaise: paise, isPersonal: isPersonal) { onDone() }
        }
    }
}

private struct ContributeSheet: View {
    let goal: Goal
    let onContribute: (Int64) -> Void

    @State private var amountStr = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Add to \"\(goal.name)\"") {
                    HStack {
                        Text("₹")
                        TextField("Amount", text: $amountStr)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Button {
                        if let paise = Formatters.parseRupeesToPaise(amountStr), paise > 0 {
                            onContribute(paise)
                            dismiss()
                        }
                    } label: {
                        Text("Add Contribution")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Contribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
