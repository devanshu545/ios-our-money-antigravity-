import Foundation

/// Mirror of `domain/LedgerCalculator.kt`. All arithmetic is integer paise and MUST stay
/// bit-identical to the Android implementation.
struct LedgerBalance: Equatable {
    var amountOwedToMePaise: Int64 = 0
    var amountIOwePaise: Int64 = 0
    /// Positive means I am ahead, negative means I am behind.
    var netBalancePaise: Int64 = 0
    var totalSharedPaidByMePaise: Int64 = 0
    var totalSharedPaidByPartnerPaise: Int64 = 0
    var myResponsibilityPaise: Int64 = 0
    var partnerResponsibilityPaise: Int64 = 0
    var totalSettlementsPaidByMePaise: Int64 = 0
    var totalSettlementsPaidByPartnerPaise: Int64 = 0
}

struct LedgerCalculator {
    func calculateNetBalance(currentUserId: String,
                             transactions: [Transaction],
                             settlements: [Settlement]) -> LedgerBalance {
        var myTotalPaid: Int64 = 0
        var partnerTotalPaid: Int64 = 0
        var myTotalResponsibility: Int64 = 0
        var partnerTotalResponsibility: Int64 = 0

        // Process ONLY Shared Transactions
        for tx in transactions {
            // Ignore Personal, Income, deleted, and Transfer transactions
            if tx.isDeleted || tx.personal || tx.type == .income || tx.type == .transfer { continue }

            // 1. Who actually paid?
            if tx.paidBy == currentUserId {
                myTotalPaid += tx.amountPaise
            } else {
                partnerTotalPaid += tx.amountPaise
            }

            // 2. Who is responsible for what portion? (kept for UI display)
            for split in tx.splits {
                if split.userId == currentUserId {
                    myTotalResponsibility += split.amountPaise
                } else {
                    partnerTotalResponsibility += split.amountPaise
                }
            }
        }

        // 50/50 SPLIT MATHEMATICAL MODEL
        // Net balance is half the difference between what I paid and what the partner paid.
        // Kotlin `/` on Long and Swift `/` on Int64 both truncate toward zero — identical results.
        var myNetBalance = (myTotalPaid - partnerTotalPaid) / 2

        var settlementsByMe: Int64 = 0
        var settlementsByPartner: Int64 = 0

        // Process Settlements
        for settlement in settlements {
            if settlement.paidBy == currentUserId {
                // I made a settlement payment to the partner. This puts me more "ahead".
                myNetBalance += settlement.amountPaise
                settlementsByMe += settlement.amountPaise
            } else if settlement.receivedBy == currentUserId {
                // I received a settlement payment from the partner. This reduces my "ahead" balance.
                myNetBalance -= settlement.amountPaise
                settlementsByPartner += settlement.amountPaise
            }
        }

        let owedToMe = myNetBalance > 0 ? myNetBalance : 0
        let iOwe = myNetBalance < 0 ? -myNetBalance : 0

        return LedgerBalance(
            amountOwedToMePaise: owedToMe,
            amountIOwePaise: iOwe,
            netBalancePaise: myNetBalance,
            totalSharedPaidByMePaise: myTotalPaid,
            totalSharedPaidByPartnerPaise: partnerTotalPaid,
            myResponsibilityPaise: myTotalResponsibility,
            partnerResponsibilityPaise: partnerTotalResponsibility,
            totalSettlementsPaidByMePaise: settlementsByMe,
            totalSettlementsPaidByPartnerPaise: settlementsByPartner
        )
    }
}
