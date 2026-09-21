import Foundation

/// Mirror of `domain/AiFinancialContextEngine.kt` — builds the text snapshot of the
/// user's real financial data that is injected into the Gemini system prompt.
struct AiFinancialContextEngine {

    func generateContext(scope: AiScope,
                         currentUser: User,
                         transactions: [Transaction],
                         budgets: [Budget],
                         goals: [Goal],
                         settlements: [Settlement]) -> String {
        var sb = ""
        sb += "CURRENT FINANCIAL STATE (Generated on \(Formatters.dayFormatter.string(from: Date())))\n"
        sb += "User Name: \(currentUser.name)\n"
        sb += "Scope: \(scope.rawValue)\n\n"

        // Filter transactions
        let activeTx = transactions.filter { !$0.isDeleted }

        // AI has full access to shared + the user's own personal data (same as Android).
        let relevantTx = activeTx.filter {
            (!$0.personal) || ($0.personal && $0.createdBy == currentUser.id)
        }

        let expenses = relevantTx.filter { $0.type == .expense }
        let totalSpent = expenses.reduce(Int64(0)) { $0 + $1.amountPaise }
        sb += "TOTAL SPENDING: ₹\(Double(totalSpent) / 100.0)\n\n"

        // Categories
        var categoryTotals: [String: Int64] = [:]
        for tx in expenses { categoryTotals[tx.category, default: 0] += tx.amountPaise }
        sb += "SPENDING BY CATEGORY:\n"
        for (cat, amount) in categoryTotals {
            sb += "- \(cat): ₹\(Double(amount) / 100.0)\n"
        }
        sb += "\n"

        // Budgets
        let relevantBudgets = budgets.filter {
            (!$0.personal) || ($0.personal && $0.createdBy == currentUser.id)
        }
        if !relevantBudgets.isEmpty {
            sb += "BUDGETS:\n"
            for b in relevantBudgets {
                let spentInCat = categoryTotals[b.category] ?? 0
                let remaining = b.limitAmountPaise - spentInCat
                let perc = b.limitAmountPaise > 0 ? (Double(spentInCat) / Double(b.limitAmountPaise) * 100) : 0.0
                sb += "- \(b.category): Limit ₹\(Double(b.limitAmountPaise) / 100.0), Spent ₹\(Double(spentInCat) / 100.0), Remaining ₹\(Double(remaining) / 100.0) (\(String(format: "%.1f", perc))% used)\n"
            }
            sb += "\n"
        }

        // Goals
        let relevantGoals = goals.filter {
            (!$0.personal) || ($0.personal && $0.createdBy == currentUser.id)
        }
        if !relevantGoals.isEmpty {
            sb += "GOALS:\n"
            for g in relevantGoals {
                let remaining = g.targetAmountPaise - g.currentAmountPaise
                let perc = g.targetAmountPaise > 0 ? (Double(g.currentAmountPaise) / Double(g.targetAmountPaise) * 100) : 0.0
                sb += "- \(g.name): Target ₹\(Double(g.targetAmountPaise) / 100.0), Saved ₹\(Double(g.currentAmountPaise) / 100.0), Remaining ₹\(Double(remaining) / 100.0) (\(String(format: "%.1f", perc))% complete)\n"
            }
            sb += "\n"
        }

        // Settlements
        let calc = LedgerCalculator().calculateNetBalance(
            currentUserId: currentUser.id,
            transactions: relevantTx,
            settlements: settlements
        )
        sb += "SETTLEMENT STATE (Shared):\n"
        sb += "- You paid total: ₹\(Double(calc.totalSharedPaidByMePaise) / 100.0)\n"
        sb += "- Friend paid total: ₹\(Double(calc.totalSharedPaidByPartnerPaise) / 100.0)\n"
        sb += "- Settlements paid by you: ₹\(Double(calc.totalSettlementsPaidByMePaise) / 100.0)\n"
        sb += "- Settlements paid by friend: ₹\(Double(calc.totalSettlementsPaidByPartnerPaise) / 100.0)\n"
        if calc.netBalancePaise > 0 {
            sb += "- Current Net Balance: You are ahead by ₹\(Double(calc.netBalancePaise) / 100.0)\n"
        } else if calc.netBalancePaise < 0 {
            sb += "- Current Net Balance: You owe ₹\(Double(calc.amountIOwePaise) / 100.0)\n"
        } else {
            sb += "- Current Net Balance: Balanced (₹0)\n"
        }
        sb += "\n"

        sb += "RECENT TRANSACTIONS (Last 10):\n"
        for tx in relevantTx.sorted(by: { $0.dateMillis > $1.dateMillis }).prefix(10) {
            let typeStr = tx.type == .expense ? "Spent" : "Earned"
            let dateStr = Formatters.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000))
            sb += "- \(dateStr): \(typeStr) ₹\(Double(tx.amountPaise) / 100.0) on \(tx.category) via \(tx.paymentMethod) (Paid by: \(tx.paidBy))\n"
        }

        return sb
    }
}
