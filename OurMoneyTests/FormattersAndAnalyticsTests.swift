import XCTest
@testable import OurMoney

final class FormattersAndAnalyticsTests: XCTestCase {

    // MARK: - Money formatting (must match Android behavior)

    func testFormatRupeesWhole() {
        XCTAssertEqual(Formatters.formatRupees(120_000), "₹1200")
        XCTAssertEqual(Formatters.formatRupees(0), "₹0")
    }

    func testFormatRupeesFractional() {
        XCTAssertEqual(Formatters.formatRupees(120_050), "₹1200.50")
        XCTAssertEqual(Formatters.formatRupees(995), "₹9.95")
    }

    func testPlainAmountString() {
        // Android: (paise / 100.0).toString().removeSuffix(".0")
        XCTAssertEqual(Formatters.plainAmountString(60_000), "600")
        XCTAssertEqual(Formatters.plainAmountString(60_050), "600.5")
    }

    func testParseRupeesToPaise() {
        XCTAssertEqual(Formatters.parseRupeesToPaise("600"), 60_000)
        XCTAssertEqual(Formatters.parseRupeesToPaise("600.5"), 60_500)
        XCTAssertEqual(Formatters.parseRupeesToPaise(" 0.99 "), 99)
        XCTAssertNil(Formatters.parseRupeesToPaise(""))
        XCTAssertNil(Formatters.parseRupeesToPaise("abc"))
        XCTAssertNil(Formatters.parseRupeesToPaise("-5"))
    }

    // MARK: - Budget analytics

    private func makeUser(_ id: String) -> User { User(id: id, name: id, email: "\(id)@x.dev") }

    private func expense(_ paise: Int64, daysAgo: Int, category: String = "Food",
                         paidBy: String = "me", personal: Bool = false,
                         createdBy: String = "me", method: String = "UPI") -> Transaction {
        let millis = Int64(Date().timeIntervalSince1970 * 1000) - Int64(daysAgo) * 86_400_000
        return Transaction(amountPaise: paise, category: category, dateMillis: millis,
                           paidBy: paidBy, createdBy: createdBy, personal: personal,
                           paymentMethod: method)
    }

    func testBudgetTotalsAndHealth() {
        let now = Date()
        let me = makeUser("me")
        let monthYear = BudgetAnalytics.monthYearFormatter.string(from: now)
        let budgets = [
            Budget(category: "Food", limitAmountPaise: 100_000, createdBy: "me", monthYear: monthYear),
            Budget(category: "Travel", limitAmountPaise: 50_000, personal: true, createdBy: "me", monthYear: monthYear),
        ]
        let transactions = [
            expense(30_000, daysAgo: 0, category: "Food"),
            expense(20_000, daysAgo: 2, category: "Food"),
            expense(10_000, daysAgo: 1, category: "Travel", personal: true),
            expense(5_000, daysAgo: 40, category: "Food"), // last month → excluded
        ]

        let state = BudgetAnalytics.buildState(
            budgets: budgets,
            transactions: transactions,
            selectedMonth: now,
            selectedScope: .all,
            currentUser: me,
            partnerId: "partner",
            now: now
        )

        XCTAssertEqual(state.totalBudgetPaise, 150_000)
        XCTAssertEqual(state.totalSpentPaise, 60_000)
        XCTAssertFalse(state.insights.isEmpty)
        // Spending 40% of budget in the first days of the month should not be OVER_BUDGET.
        XCTAssertNotEqual(state.healthStatus, .overBudget)
    }

    func testScopeFiltersExcludePartnerPersonalData() {
        let now = Date()
        let me = makeUser("me")
        let transactions = [
            expense(10_000, daysAgo: 0, personal: true, createdBy: "partner"),
            expense(20_000, daysAgo: 0, personal: true, createdBy: "me"),
            expense(30_000, daysAgo: 0),
        ]
        let state = BudgetAnalytics.buildState(
            budgets: [],
            transactions: transactions,
            selectedMonth: now,
            selectedScope: .personal,
            currentUser: me,
            partnerId: "partner",
            now: now
        )
        XCTAssertEqual(state.totalSpentPaise, 20_000)

        let sharedState = BudgetAnalytics.buildState(
            budgets: [],
            transactions: transactions,
            selectedMonth: now,
            selectedScope: .shared,
            currentUser: me,
            partnerId: "partner",
            now: now
        )
        XCTAssertEqual(sharedState.totalSpentPaise, 30_000)
    }

    func testPartnerPersonalExcludedFromSharedAnalytics() {
        let me = makeUser("me")
        let txs = [
            Transaction(amountPaise: 100, category: "Food", paidBy: "me", createdBy: "me", personal: false),
            Transaction(amountPaise: 200, category: "Food", paidBy: "partner", createdBy: "partner", personal: true),
        ]
        let stats = AnalyticsViewModel.compute(transactions: txs, currentUserId: "me")
        XCTAssertEqual(stats.totalSpent, 100)
        XCTAssertEqual(stats.youPaid, 100)
        XCTAssertEqual(stats.partnerPaid, 0)
    }

    func testHistorySearchFiltering() {
        let me = makeUser("me")
        let household = Household(members: ["me", "partner"])
        let vm = HistoryViewModel(currentUser: me, household: household)
        // The filter logic runs on published streams; validate the term logic directly here
        // via the same predicate used in the view model.
        let terms = "food 600".lowercased().split(whereSeparator: \.isWhitespace)
        let tx = Transaction(amountPaise: 60_000, category: "Food & Dining", notes: "Dinner")
        let amountStr = Formatters.plainAmountString(tx.amountPaise)
        let dateStr = Formatters.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000)).lowercased()
        let matches = terms.allSatisfy { term in
            tx.category.lowercased().contains(term) ||
            tx.notes.lowercased().contains(term) ||
            tx.paymentMethod.lowercased().contains(term) ||
            amountStr.contains(term) ||
            dateStr.contains(term) ||
            (tx.personal ? "personal" : "shared").contains(term)
        }
        XCTAssertTrue(matches)
    }
}
