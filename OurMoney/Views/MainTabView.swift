import SwiftUI

/// Mirror of `ui/main/MainScreen.kt`: 6-tab bottom navigation with native iOS sheets
/// for Add Expense / Settle Up / Settings.
struct MainTabView: View {
    let user: User
    let household: Household

    enum Tab: Hashable {
        case home, history, stats, budgets, goals, ai
    }

    @State private var selectedTab: Tab = .home
    @State private var showAddExpense = false
    @State private var editExpenseId: String?
    @State private var showSettleUp = false
    @State private var editSettlementId: String?
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                user: user,
                household: household,
                onAddExpense: { editExpenseId = nil; showAddExpense = true },
                onEditExpense: { id in editExpenseId = id; showAddExpense = true },
                onSettleUp: { editSettlementId = nil; showSettleUp = true },
                onSettings: { showSettings = true }
            )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            HistoryView(
                user: user,
                household: household,
                onEditExpense: { id in editExpenseId = id; showAddExpense = true },
                onEditSettlement: { id in editSettlementId = id; showSettleUp = true }
            )
            .tabItem { Label("History", systemImage: "list.bullet") }
            .tag(Tab.history)

            AnalyticsView(user: user, household: household)
                .tabItem { Label("Stats", systemImage: "chart.pie.fill") }
                .tag(Tab.stats)

            BudgetsView(user: user, household: household)
                .tabItem { Label("Budgets", systemImage: "checkmark.circle.fill") }
                .tag(Tab.budgets)

            GoalsView(user: user, household: household)
                .tabItem { Label("Goals", systemImage: "checkmark.circle") }
                .tag(Tab.goals)

            AiView(user: user, household: household)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(Tab.ai)
        }
        .sheet(isPresented: $showAddExpense) {
            NavigationStack {
                AddExpenseView(user: user, household: household, transactionId: editExpenseId) {
                    showAddExpense = false
                }
            }
        }
        .sheet(isPresented: $showSettleUp) {
            NavigationStack {
                SettleUpView(user: user, household: household, settlementId: editSettlementId) {
                    showSettleUp = false
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(user: user, household: household)
            }
        }
    }
}
