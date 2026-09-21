import Foundation

/// Port of the analytics inside `ui/budgets/BudgetsScreen.kt` (BudgetsViewModel.buildState).
/// All arithmetic matches the Android implementation; `monthYear` strings use "MM-yyyy".
enum BudgetScope: String, CaseIterable {
    case all = "All"
    case shared = "Shared"
    case personal = "Personal"
}

enum BudgetHealth: String {
    case onTrack = "ON TRACK"
    case watch = "WATCH"
    case atRisk = "AT RISK"
    case overBudget = "OVER BUDGET"
}

struct WeeklyDayStat {
    let dayName: String
    let spentPaise: Int64
    let dateMillis: Int64
}

struct CategoryStat: Identifiable {
    let budget: Budget
    let spentPaise: Int64
    let totalTransactions: Int
    let largestTransaction: Int64
    let averageTransaction: Int64
    let transactions: [Transaction]

    var id: String { budget.id }
}

struct ComprehensiveBudgetState {
    let monthYearStr: String
    let monthName: String
    let totalBudgetPaise: Int64
    let totalSpentPaise: Int64
    let spentTodayPaise: Int64
    let safeDailyLimitPaise: Int64
    let spentThisWeekPaise: Int64
    let weeklyBudgetPaise: Int64
    let expectedMonthEndPaise: Int64
    let expectedRemainingPaise: Int64
    let daysInMonth: Int
    let daysElapsed: Int
    let daysRemaining: Int
    let healthStatus: BudgetHealth
    let categories: [CategoryStat]
    let weeklyChartData: [WeeklyDayStat]
    let spentLastWeekPaise: Int64
    let spentLastMonthPaise: Int64
    let upiSpentPaise: Int64
    let cashSpentPaise: Int64
    let currentUserSpentPaise: Int64
    let partnerSpentPaise: Int64
    let currentUserResponsiblePaise: Int64
    let partnerResponsiblePaise: Int64
    let insights: [String]
}

enum BudgetAnalytics {

    static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-yyyy"
        return f
    }()

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        return f
    }()

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Pure computation ported 1:1 from Android `buildState`.
    static func buildState(budgets: [Budget],
                           transactions: [Transaction],
                           selectedMonth: Date,
                           selectedScope: BudgetScope,
                           currentUser: User,
                           partnerId: String,
                           now: Date = Date()) -> ComprehensiveBudgetState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let monthCal = calendar.dateComponents([.year, .month], from: selectedMonth)
        let nowCal = calendar.dateComponents([.year, .month, .day], from: now)

        let isCurrentMonth = monthCal.year == nowCal.year && monthCal.month == nowCal.month
        let isPastMonth = selectedMonth < now && !isCurrentMonth

        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30

        let daysElapsed: Int
        if isPastMonth {
            daysElapsed = daysInMonth
        } else if isCurrentMonth {
            daysElapsed = nowCal.day ?? 1
        } else {
            daysElapsed = 0
        }

        let daysRemaining = isPastMonth ? 0 : max(1, daysInMonth - daysElapsed)

        let currentMonthYear = monthYearFormatter.string(from: selectedMonth)
        let monthName = Formatters.monthNameFormatter.string(from: selectedMonth)

        // Reference day: today if current month, last day if past month, 1st if future.
        let referenceDay: Date
        if isCurrentMonth {
            referenceDay = now
        } else if isPastMonth {
            var comps = monthCal
            comps.day = daysInMonth
            referenceDay = calendar.date(from: comps) ?? selectedMonth
        } else {
            var comps = monthCal
            comps.day = 1
            referenceDay = calendar.date(from: comps) ?? selectedMonth
        }
        let referenceDayStr = dayKeyFormatter.string(from: referenceDay)

        // Week containing the reference day (weeks start on Monday, like Android Calendar.MONDAY).
        var weekCal = calendar
        weekCal.firstWeekday = 2 // Monday
        // Walk back from the reference day to that week's Monday 00:00.
        let referenceStart = calendar.startOfDay(for: referenceDay)
        let referenceWeekday = calendar.component(.weekday, from: referenceStart) // 1=Sun..7=Sat
        let daysFromMonday = (referenceWeekday + 5) % 7
        let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: referenceStart) ?? referenceStart
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? startOfWeek
        let startOfLastWeek = calendar.date(byAdding: .day, value: -14, to: startOfWeek) ?? startOfWeek
        let endOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfWeek) ?? startOfWeek

        var lastMonthComps = DateComponents()
        lastMonthComps.month = -1
        let lastMonthDate = calendar.date(byAdding: lastMonthComps, to: selectedMonth) ?? selectedMonth
        let lastMonthYear = monthYearFormatter.string(from: lastMonthDate)

        // Filter budgets by scope
        let scopedBudgets = budgets.filter { budget -> Bool in
            switch selectedScope {
            case .all: return budget.personal ? budget.createdBy == currentUser.id : true
            case .shared: return !budget.personal
            case .personal: return budget.personal && budget.createdBy == currentUser.id
            }
        }
        let currentMonthBudgets = scopedBudgets.filter { $0.monthYear == currentMonthYear }
        let totalBudgetPaise = currentMonthBudgets.reduce(Int64(0)) { $0 + $1.limitAmountPaise }

        // Filter transactions by scope
        let scopedTransactions = transactions.filter { tx -> Bool in
            switch selectedScope {
            case .all: return tx.personal ? tx.createdBy == currentUser.id : true
            case .shared: return !tx.personal
            case .personal: return tx.personal && tx.createdBy == currentUser.id
            }
        }
        let expenses = scopedTransactions.filter { $0.type == .expense && !$0.isDeleted }
        let currentMonthTxs = expenses.filter { monthYearFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.dateMillis) / 1000)) == currentMonthYear }
        let lastMonthTxs = expenses.filter { monthYearFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.dateMillis) / 1000)) == lastMonthYear }

        let totalSpentPaise = currentMonthTxs.reduce(Int64(0)) { $0 + $1.amountPaise }
        let spentTodayPaise = currentMonthTxs
            .filter { dayKeyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.dateMillis) / 1000)) == referenceDayStr }
            .reduce(Int64(0)) { $0 + $1.amountPaise }
        let spentThisWeekPaise = currentMonthTxs
            .filter { $0.dateMillis >= Int64(startOfWeek.timeIntervalSince1970 * 1000) && $0.dateMillis < Int64(endOfWeek.timeIntervalSince1970 * 1000) }
            .reduce(Int64(0)) { $0 + $1.amountPaise }
        let spentLastWeekPaise = expenses
            .filter { $0.dateMillis >= Int64(startOfLastWeek.timeIntervalSince1970 * 1000) && $0.dateMillis < Int64(endOfLastWeek.timeIntervalSince1970 * 1000) }
            .reduce(Int64(0)) { $0 + $1.amountPaise }
        let spentLastMonthPaise = lastMonthTxs.reduce(Int64(0)) { $0 + $1.amountPaise }

        let remainingPaise = totalBudgetPaise - totalSpentPaise
        let safeDailyLimitPaise: Int64 = (remainingPaise > 0 && daysRemaining > 0) ? remainingPaise / Int64(daysRemaining) : 0
        let weeklyBudgetPaise: Int64 = daysInMonth > 0 ? (totalBudgetPaise / Int64(daysInMonth)) * 7 : 0

        let averageDailySpent: Int64 = daysElapsed > 0 ? totalSpentPaise / Int64(daysElapsed) : 0
        let expectedMonthEndPaise = totalSpentPaise + (averageDailySpent * Int64(daysRemaining))
        let expectedRemainingPaise = totalBudgetPaise - expectedMonthEndPaise

        let budgetUsedPct: Double = totalBudgetPaise > 0 ? Double(totalSpentPaise) / Double(totalBudgetPaise) : 0
        let timeElapsedPct: Double = daysInMonth > 0 ? Double(daysElapsed) / Double(daysInMonth) : 0

        let healthStatus: BudgetHealth
        if totalSpentPaise > totalBudgetPaise {
            healthStatus = .overBudget
        } else if budgetUsedPct > timeElapsedPct + 0.1 {
            healthStatus = .atRisk
        } else if budgetUsedPct > timeElapsedPct {
            healthStatus = .watch
        } else {
            healthStatus = .onTrack
        }

        // Categories
        let categories = currentMonthBudgets.map { budget -> CategoryStat in
            let catTxs = currentMonthTxs.filter {
                $0.category.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(
                    budget.category.trimmingCharacters(in: .whitespaces)) == .orderedSame && $0.personal == budget.personal
            }
            let spent = catTxs.reduce(Int64(0)) { $0 + $1.amountPaise }
            return CategoryStat(
                budget: budget,
                spentPaise: spent,
                totalTransactions: catTxs.count,
                largestTransaction: catTxs.map(\.amountPaise).max() ?? 0,
                averageTransaction: catTxs.isEmpty ? 0 : spent / Int64(catTxs.count),
                transactions: catTxs.sorted { $0.dateMillis > $1.dateMillis }
            )
        }.sorted { $0.spentPaise > $1.spentPaise }

        // Weekly chart data (Mon..Sun of the reference week)
        var weeklyChartData: [WeeklyDayStat] = []
        for i in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: i, to: startOfWeek) else { continue }
            let startOfDay = calendar.startOfDay(for: day)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }
            let daySpent = currentMonthTxs
                .filter { $0.dateMillis >= Int64(startOfDay.timeIntervalSince1970 * 1000) && $0.dateMillis < Int64(endOfDay.timeIntervalSince1970 * 1000) }
                .reduce(Int64(0)) { $0 + $1.amountPaise }
            weeklyChartData.append(WeeklyDayStat(
                dayName: weekdayFormatter.string(from: startOfDay),
                spentPaise: daySpent,
                dateMillis: Int64(startOfDay.timeIntervalSince1970 * 1000)
            ))
        }

        // Payment methods
        let upiSpentPaise = currentMonthTxs.filter { $0.paymentMethod.range(of: "UPI", options: .caseInsensitive) != nil }
            .reduce(Int64(0)) { $0 + $1.amountPaise }
        let cashSpentPaise = currentMonthTxs.filter { $0.paymentMethod.range(of: "Cash", options: .caseInsensitive) != nil }
            .reduce(Int64(0)) { $0 + $1.amountPaise }

        // Two-person split logic
        var currentUserSpent: Int64 = 0
        var partnerSpent: Int64 = 0
        var currentUserResp: Int64 = 0
        var partnerResp: Int64 = 0

        for tx in currentMonthTxs {
            if tx.paidBy == currentUser.id {
                currentUserSpent += tx.amountPaise
            } else if tx.paidBy == partnerId {
                partnerSpent += tx.amountPaise
            }

            if tx.personal {
                if tx.createdBy == currentUser.id { currentUserResp += tx.amountPaise }
                else { partnerResp += tx.amountPaise }
            } else {
                switch tx.splitMethod {
                case .equal:
                    currentUserResp += tx.amountPaise / 2
                    partnerResp += tx.amountPaise / 2
                case .exact:
                    for split in tx.splits {
                        if split.userId == currentUser.id { currentUserResp += split.amountPaise }
                        else if split.userId == partnerId { partnerResp += split.amountPaise }
                    }
                default:
                    currentUserResp += tx.amountPaise / 2
                    partnerResp += tx.amountPaise / 2
                }
            }
        }

        // Insights
        var insights: [String] = []
        if spentThisWeekPaise < spentLastWeekPaise && spentLastWeekPaise > 0 {
            insights.append("You spent \(Formatters.formatRupees(spentLastWeekPaise - spentThisWeekPaise)) less this week than last week.")
        }
        if averageDailySpent > safeDailyLimitPaise && safeDailyLimitPaise > 0 {
            insights.append("You're spending \(Formatters.formatRupees(averageDailySpent - safeDailyLimitPaise))/day faster than your safe rate.")
        }
        if let first = categories.first {
            let pct = Int(Double(first.spentPaise) / Double(max(1, totalSpentPaise)) * 100)
            insights.append("\(first.budget.category) accounts for \(pct)% of your spending.")
        }
        if expectedMonthEndPaise < totalBudgetPaise && totalBudgetPaise > 0 {
            insights.append("You're currently on pace to finish \(Formatters.formatRupees(expectedRemainingPaise)) under budget.")
        }

        return ComprehensiveBudgetState(
            monthYearStr: currentMonthYear,
            monthName: monthName,
            totalBudgetPaise: totalBudgetPaise,
            totalSpentPaise: totalSpentPaise,
            spentTodayPaise: spentTodayPaise,
            safeDailyLimitPaise: safeDailyLimitPaise,
            spentThisWeekPaise: spentThisWeekPaise,
            weeklyBudgetPaise: weeklyBudgetPaise,
            expectedMonthEndPaise: expectedMonthEndPaise,
            expectedRemainingPaise: expectedRemainingPaise,
            daysInMonth: daysInMonth,
            daysElapsed: daysElapsed,
            daysRemaining: daysRemaining,
            healthStatus: healthStatus,
            categories: categories,
            weeklyChartData: weeklyChartData,
            spentLastWeekPaise: spentLastWeekPaise,
            spentLastMonthPaise: spentLastMonthPaise,
            upiSpentPaise: upiSpentPaise,
            cashSpentPaise: cashSpentPaise,
            currentUserSpentPaise: currentUserSpent,
            partnerSpentPaise: partnerSpent,
            currentUserResponsiblePaise: currentUserResp,
            partnerResponsiblePaise: partnerResp,
            insights: insights
        )
    }
}
