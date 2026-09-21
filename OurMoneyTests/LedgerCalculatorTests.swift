import XCTest
@testable import OurMoney

/// Financial math must stay bit-identical with the Android implementation.
final class LedgerCalculatorTests: XCTestCase {

    let calculator = LedgerCalculator()
    let me = "user-me"
    let partner = "user-partner"

    private func tx(_ amountPaise: Int64,
                    paidBy: String,
                    personal: Bool = false,
                    type: TransactionType = .expense,
                    deleted: Bool = false,
                    splits: [SplitAmount] = [],
                    method: SplitMethod = .equal) -> Transaction {
        var tx = Transaction(
            amountPaise: amountPaise,
            category: "Food",
            paidBy: paidBy,
            createdBy: paidBy,
            personal: personal,
            splitMethod: method,
            splits: splits,
            type: type
        )
        tx.isDeleted = deleted
        return tx
    }

    func testSpecExample_rupees2000_devanshu1200_friend800() {
        // Spec: Total ₹2000. Devanshu paid ₹1200, friend paid ₹800, 50/50 split.
        // Each share ₹1000 → friend owes Devanshu ₹200.
        let transactions = [
            tx(120_000, paidBy: me),
            tx(80_000, paidBy: partner),
        ]
        let balance = calculator.calculateNetBalance(currentUserId: me, transactions: transactions, settlements: [])

        XCTAssertEqual(balance.netBalancePaise, 20_000)          // +₹200 ahead
        XCTAssertEqual(balance.amountOwedToMePaise, 20_000)      // friend owes me ₹200
        XCTAssertEqual(balance.amountIOwePaise, 0)
        XCTAssertEqual(balance.totalSharedPaidByMePaise, 120_000)
        XCTAssertEqual(balance.totalSharedPaidByPartnerPaise, 80_000)
        // From the partner's perspective the sign flips.
        let partnerBalance = calculator.calculateNetBalance(currentUserId: partner, transactions: transactions, settlements: [])
        XCTAssertEqual(partnerBalance.amountIOwePaise, 20_000)
    }

    func testNegativeNetTruncatesTowardZero_likeKotlin() {
        // Kotlin Long division and Swift Int64 division both truncate toward zero.
        // myPaid=1 paise, partner=0 → (1-0)/2 = 0 in both languages.
        let transactions = [tx(1, paidBy: me)]
        let balance = calculator.calculateNetBalance(currentUserId: me, transactions: transactions, settlements: [])
        XCTAssertEqual(balance.netBalancePaise, 0)

        // And (0-1)/2 = 0 in both (not -1).
        let balance2 = calculator.calculateNetBalance(currentUserId: partner, transactions: transactions, settlements: [])
        XCTAssertEqual(balance2.netBalancePaise, 0)
    }

    func testPersonalIncomeTransferAndDeletedAreIgnored() {
        let transactions = [
            tx(50_000, paidBy: me, personal: true),          // personal → ignored
            tx(30_000, paidBy: me, type: .income),           // income → ignored
            tx(20_000, paidBy: me, type: .transfer),         // transfer → ignored
            tx(10_000, paidBy: me, deleted: true),           // deleted → ignored
            tx(100_000, paidBy: partner),                    // counted
        ]
        let balance = calculator.calculateNetBalance(currentUserId: me, transactions: transactions, settlements: [])
        XCTAssertEqual(balance.totalSharedPaidByMePaise, 0)
        XCTAssertEqual(balance.totalSharedPaidByPartnerPaise, 100_000)
        XCTAssertEqual(balance.netBalancePaise, -50_000)     // (0 - 100000)/2
        XCTAssertEqual(balance.amountIOwePaise, 50_000)
    }

    func testSettlementPaidByMeIncreasesBalance() {
        let balance = calculator.calculateNetBalance(
            currentUserId: me,
            transactions: [tx(100_000, paidBy: partner)],
            settlements: [Settlement(amountPaise: 30_000, paidBy: me, receivedBy: partner)]
        )
        // (0-100000)/2 + 30000 = -20000 → I owe ₹200 after paying ₹300 toward a ₹500 debt.
        XCTAssertEqual(balance.netBalancePaise, -20_000)
        XCTAssertEqual(balance.totalSettlementsPaidByMePaise, 30_000)
    }

    func testSettlementReceivedByMeDecreasesBalance() {
        let balance = calculator.calculateNetBalance(
            currentUserId: me,
            transactions: [tx(100_000, paidBy: me)],
            settlements: [Settlement(amountPaise: 30_000, paidBy: partner, receivedBy: me)]
        )
        XCTAssertEqual(balance.netBalancePaise, 20_000)
        XCTAssertEqual(balance.totalSettlementsPaidByPartnerPaise, 30_000)
    }

    func testResponsibilitySplitsAreTracked() {
        let splits = [SplitAmount(userId: me, amountPaise: 60_000),
                      SplitAmount(userId: partner, amountPaise: 40_000)]
        let balance = calculator.calculateNetBalance(
            currentUserId: me,
            transactions: [tx(100_000, paidBy: me, splits: splits, method: .exact)],
            settlements: []
        )
        XCTAssertEqual(balance.myResponsibilityPaise, 60_000)
        XCTAssertEqual(balance.partnerResponsibilityPaise, 40_000)
        // Net still uses the 50/50 model regardless of exact splits.
        XCTAssertEqual(balance.netBalancePaise, 50_000)
    }

    func testEmptyLedgerIsZero() {
        let balance = calculator.calculateNetBalance(currentUserId: me, transactions: [], settlements: [])
        XCTAssertEqual(balance.netBalancePaise, 0)
        XCTAssertEqual(balance.amountOwedToMePaise, 0)
        XCTAssertEqual(balance.amountIOwePaise, 0)
    }
}
