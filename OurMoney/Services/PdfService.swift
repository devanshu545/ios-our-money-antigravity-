import Foundation
import UIKit

/// iOS port of `util/PdfGenerator.kt`. Produces the same A4 report (595x842 pt) with the
/// same sections and colors, then hands the file to the iOS share sheet.
enum PdfService {

    /// Drawing cursor: tracks the current y position across closures.
    final class Cursor {
        var y: CGFloat
        init(_ y: CGFloat) { self.y = y }
    }

    static func generateReport(transactions: [Transaction],
                               allScopeTransactions: [Transaction],
                               budgets: [Budget],
                               currentUser: User,
                               partnerUser: User?,
                               scopeName: String,
                               periodName: String,
                               reportType: String,
                               startDateMillis: Int64,
                               endDateMillis: Int64) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "OurMoney",
            kCGPDFContextTitle as String: "\(reportType) Report",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let sdfDate = Formatters.dayFormatter
        let generatedDate = sdfDate.string(from: Date())
        let dateStr = (startDateMillis > 0 && endDateMillis > 0)
            ? "\(sdfDate.string(from: Date(timeIntervalSince1970: TimeInterval(startDateMillis) / 1000))) - \(sdfDate.string(from: Date(timeIntervalSince1970: TimeInterval(endDateMillis) / 1000)))"
            : periodName

        // Colors (same palette as the Android PDF engine)
        let colorBrand = UIColor(red: 0x33/255, green: 0x66/255, blue: 0xFF/255, alpha: 1)
        let colorTextPrimary = UIColor(red: 0x22/255, green: 0x2B/255, blue: 0x45/255, alpha: 1)
        let colorTextSecondary = UIColor(red: 0x8F/255, green: 0x9B/255, blue: 0xB3/255, alpha: 1)
        let colorSuccess = UIColor(red: 0x00/255, green: 0xE0/255, blue: 0x96/255, alpha: 1)
        let colorWarning = UIColor(red: 0xFF/255, green: 0xAA/255, blue: 0x00/255, alpha: 1)
        let colorDanger = UIColor(red: 0xFF/255, green: 0x3D/255, blue: 0x71/255, alpha: 1)
        let colorBackground = UIColor(red: 0xF7/255, green: 0xF9/255, blue: 0xFC/255, alpha: 1)
        let colorDivider = UIColor(red: 0xED/255, green: 0xF1/255, blue: 0xF7/255, alpha: 1)

        let margin: CGFloat = 50
        let pageWidth = pageRect.width
        let pageHeight = pageRect.height
        let cursor = Cursor(0)
        var pageNumber = 0

        func draw(_ text: String, x: CGFloat, size: CGFloat, color: UIColor, bold: Bool, align: NSTextAlignment = .left) {
            let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let nsText = text as NSString
            let bounds = nsText.size(withAttributes: attrs)
            let drawX: CGFloat
            switch align {
            case .right: drawX = x - bounds.width
            case .center: drawX = x - bounds.width / 2
            default: drawX = x
            }
            nsText.draw(at: CGPoint(x: drawX, y: cursor.y), withAttributes: attrs)
        }

        func drawLine(color: UIColor, strokeWidth: CGFloat) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: cursor.y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: cursor.y))
            color.setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        }

        func newPage(context: UIGraphicsPDFRendererContext) {
            pageNumber += 1
            context.beginPage()
            cursor.y = margin
            if pageNumber > 1 {
                draw("OURMONEY", x: margin, size: 10, color: colorTextSecondary, bold: false)
                draw(dateStr, x: pageWidth - margin, size: 10, color: colorTextSecondary, bold: false, align: .right)
                draw("Page \(pageNumber)", x: pageWidth / 2 - 20, size: 10, color: colorTextSecondary, bold: false)
            }
            cursor.y += 20
        }

        let data = renderer.pdfData { ctx in
            newPage(context: ctx)

            // 1. Report header
            draw("OURMONEY", x: margin, size: 28, color: colorBrand, bold: true)
            draw("Generated: \(generatedDate)", x: pageWidth - margin, size: 12, color: colorTextSecondary, bold: false, align: .right)
            cursor.y += 16
            draw("Scope: \(scopeName)", x: pageWidth - margin, size: 12, color: colorTextSecondary, bold: false, align: .right)
            cursor.y += 40
            draw("Personal Finance Report", x: margin, size: 14, color: colorTextSecondary, bold: false)
            cursor.y += 24
            draw("\(reportType) Report", x: margin, size: 22, color: colorTextPrimary, bold: true)
            cursor.y += 20
            draw(dateStr, x: margin, size: 14, color: colorTextPrimary, bold: false)
            cursor.y += 30
            drawLine(color: colorDivider, strokeWidth: 2)
            cursor.y += 30

            guard !transactions.isEmpty else {
                draw("Total Spending", x: margin, size: 14, color: colorTextSecondary, bold: false)
                cursor.y += 30
                draw("₹0", x: margin, size: 36, color: colorTextPrimary, bold: true)
                cursor.y += 40
                draw("No transactions were recorded during this period.", x: margin, size: 14, color: colorTextPrimary, bold: false)
                return
            }

            let totalSpent = transactions.reduce(Int64(0)) { $0 + $1.amountPaise }
            let totalBudget = budgets.reduce(Int64(0)) { $0 + $1.limitAmountPaise }
            let remainingBudget = totalBudget - totalSpent
            let budgetUsedPct: Double = totalBudget > 0 ? Double(totalSpent) / Double(totalBudget) * 100 : 0

            // 2. Budget performance
            draw("BUDGET PERFORMANCE", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25
            draw("Total Spending", x: margin, size: 12, color: colorTextSecondary, bold: true)
            if totalBudget > 0 {
                draw("Budget", x: pageWidth / 2, size: 12, color: colorTextSecondary, bold: true)
                draw("Remaining", x: pageWidth - margin, size: 12, color: colorTextSecondary, bold: true, align: .right)
            }
            cursor.y += 35
            draw(Formatters.formatRupees(totalSpent), x: margin, size: 32, color: colorTextPrimary, bold: true)
            if totalBudget > 0 {
                draw(Formatters.formatRupees(totalBudget), x: pageWidth / 2, size: 20, color: colorTextPrimary, bold: true)
                draw(Formatters.formatRupees(remainingBudget), x: pageWidth - margin, size: 20,
                     color: remainingBudget >= 0 ? colorSuccess : colorDanger, bold: true, align: .right)
                cursor.y += 20
                let barY = cursor.y + 10
                colorDivider.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: barY, width: pageWidth - 2 * margin, height: 8), cornerRadius: 4).fill()
                let fillWidth = max(0, min(1, budgetUsedPct / 100)) * (pageWidth - 2 * margin)
                (budgetUsedPct <= 80 ? colorSuccess : budgetUsedPct <= 100 ? colorWarning : colorDanger).setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: barY, width: fillWidth, height: 8), cornerRadius: 4).fill()
                cursor.y += 30
                draw("Budget Used: \(String(format: "%.1f", budgetUsedPct))%", x: margin, size: 12, color: colorTextSecondary, bold: false)
                cursor.y += 20
            }

            // 3. Status chip
            if totalBudget > 0 {
                let status: (String, String, UIColor) = {
                    if budgetUsedPct > 100 { return ("OVER BUDGET", "Spending has exceeded the total allocated budget.", colorDanger) }
                    if budgetUsedPct > 85 { return ("AT RISK", "Spending is close to exceeding the budget limit.", colorWarning) }
                    if budgetUsedPct > 50 { return ("WATCH", "Spending is progressing steadily.", colorBrand) }
                    return ("ON TRACK", "Spending is well within the budget limits.", colorSuccess)
                }()
                status.2.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: cursor.y, width: 100, height: 24), cornerRadius: 12).fill()
                draw(status.0, x: margin + 50, size: 12, color: .white, bold: true, align: .center)
                cursor.y += 17
                draw(status.1, x: margin + 115, size: 12, color: colorTextSecondary, bold: false)
                cursor.y += 30
            }

            drawLine(color: colorDivider, strokeWidth: 1)
            cursor.y += 30

            // 4. At a glance
            draw(reportType.lowercased() == "weekly" ? "WEEK AT A GLANCE" : "MONTH AT A GLANCE", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25

            let daysInPeriod: Int64 = (startDateMillis > 0 && endDateMillis > 0)
                ? max(1, (endDateMillis - startDateMillis) / (1000 * 60 * 60 * 24))
                : (reportType == "Weekly" ? 7 : 30)
            let avgDaily = totalSpent / daysInPeriod

            var dailyTotals: [String: Int64] = [:]
            for tx in transactions {
                let key = Formatters.shortDayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000))
                dailyTotals[key, default: 0] += tx.amountPaise
            }
            let highestDay = dailyTotals.max { $0.value < $1.value }
            var categoryTotals: [String: Int64] = [:]
            for tx in transactions { categoryTotals[tx.category, default: 0] += tx.amountPaise }
            let highestCategory = categoryTotals.max { $0.value < $1.value }

            let exCol1 = margin
            let exCol2 = pageWidth / 2 + 20

            draw("Total Transactions", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
            draw("\(transactions.count)", x: exCol1, size: 14, color: colorTextPrimary, bold: true)
            draw("Average Daily Spend", x: exCol2, size: 12, color: colorTextSecondary, bold: false)
            draw(Formatters.formatRupees(avgDaily), x: exCol2, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 35

            draw("Highest Spending Day", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
            draw(highestDay.map { "\($0.key) (\(Formatters.formatRupees($0.value)))" } ?? "-", x: exCol1, size: 14, color: colorTextPrimary, bold: true)
            draw("Highest Category", x: exCol2, size: 12, color: colorTextSecondary, bold: false)
            draw(highestCategory.map { "\($0.key) (\(Formatters.formatRupees($0.value)))" } ?? "-", x: exCol2, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 40

            // Period comparison
            if startDateMillis > 0 && endDateMillis > 0 {
                let periodLen = endDateMillis - startDateMillis
                let prevStart = startDateMillis - periodLen - 1
                let prevEnd = startDateMillis - 1
                let prevTxs = allScopeTransactions.filter { $0.dateMillis >= prevStart && $0.dateMillis <= prevEnd }
                if !prevTxs.isEmpty {
                    let prevSpent = prevTxs.reduce(Int64(0)) { $0 + $1.amountPaise }
                    draw("PERIOD COMPARISON", x: margin, size: 14, color: colorTextPrimary, bold: true)
                    cursor.y += 25
                    draw("Current Period", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
                    draw(Formatters.formatRupees(totalSpent), x: exCol1, size: 14, color: colorTextPrimary, bold: true)
                    draw("Previous Period", x: exCol2, size: 12, color: colorTextSecondary, bold: false)
                    draw(Formatters.formatRupees(prevSpent), x: exCol2, size: 14, color: colorTextPrimary, bold: true)

                    let diff = totalSpent - prevSpent
                    let pct = prevSpent > 0 ? Double(diff) / Double(prevSpent) * 100 : 0
                    let diffText: String
                    if diff > 0 { diffText = "↑ \(String(format: "%.1f", pct))% increase" }
                    else if diff < 0 { diffText = "↓ \(String(format: "%.1f", -pct))% decrease" }
                    else { diffText = "Unchanged" }
                    cursor.y += 25
                    draw("Change: \(diffText)", x: exCol1, size: 14, color: diff > 0 ? colorDanger : colorSuccess, bold: true)
                    cursor.y += 30
                }
            }

            // Shared expense summary
            if (scopeName == "Shared" || scopeName == "All"), let partnerUser {
                drawLine(color: colorDivider, strokeWidth: 1)
                cursor.y += 30
                draw("SHARED EXPENSE SUMMARY", x: margin, size: 14, color: colorTextPrimary, bold: true)
                cursor.y += 25

                let sharedTxs = transactions.filter { !$0.personal }
                var myPaid: Int64 = 0, partnerPaid: Int64 = 0, myResp: Int64 = 0, partnerResp: Int64 = 0
                for tx in sharedTxs {
                    if tx.paidBy == currentUser.id { myPaid += tx.amountPaise } else { partnerPaid += tx.amountPaise }
                    if tx.splitMethod == .exact {
                        for split in tx.splits {
                            if split.userId == currentUser.id { myResp += split.amountPaise }
                            else { partnerResp += split.amountPaise }
                        }
                    } else {
                        myResp += tx.amountPaise / 2
                        partnerResp += tx.amountPaise / 2
                    }
                }

                draw("\(currentUser.name) Paid", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
                draw(Formatters.formatRupees(myPaid), x: exCol1, size: 14, color: colorTextPrimary, bold: true)
                draw("\(partnerUser.name) Paid", x: exCol2, size: 12, color: colorTextSecondary, bold: false)
                draw(Formatters.formatRupees(partnerPaid), x: exCol2, size: 14, color: colorTextPrimary, bold: true)
                cursor.y += 35
                draw("\(currentUser.name) Share", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
                draw(Formatters.formatRupees(myResp), x: exCol1, size: 14, color: colorTextPrimary, bold: true)
                draw("\(partnerUser.name) Share", x: exCol2, size: 12, color: colorTextSecondary, bold: false)
                draw(Formatters.formatRupees(partnerResp), x: exCol2, size: 14, color: colorTextPrimary, bold: true)
                cursor.y += 35

                let net = myPaid - myResp
                let settleText: String
                if net > 0 { settleText = "\(partnerUser.name) owes you \(Formatters.formatRupees(net))" }
                else if net < 0 { settleText = "You owe \(partnerUser.name) \(Formatters.formatRupees(-net))" }
                else { settleText = "Settled up" }
                draw("Net Settlement", x: exCol1, size: 12, color: colorTextSecondary, bold: false)
                draw(settleText, x: exCol1, size: 14, color: colorBrand, bold: true)
                cursor.y += 40
            }

            // Insights
            drawLine(color: colorDivider, strokeWidth: 1)
            cursor.y += 30
            draw(reportType.lowercased() == "weekly" ? "WEEKLY INSIGHTS" : "MONTHLY INSIGHTS", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25
            if let highestCategory {
                let pct = Int(Double(highestCategory.value) / Double(totalSpent) * 100)
                draw("• \(highestCategory.key) accounted for \(pct)% of total spending.", x: margin, size: 12, color: colorTextPrimary, bold: false)
                cursor.y += 20
            }
            draw("• Your average daily spending was \(Formatters.formatRupees(avgDaily)).", x: margin, size: 12, color: colorTextPrimary, bold: false)
            cursor.y += 20
            if totalBudget > 0 {
                if budgetUsedPct < 100 {
                    draw("• You are on track and have \(Formatters.formatRupees(remainingBudget)) remaining in your budget.", x: margin, size: 12, color: colorSuccess, bold: false)
                } else {
                    draw("• You have exceeded your budget by \(Formatters.formatRupees(-remainingBudget)).", x: margin, size: 12, color: colorDanger, bold: false)
                }
                cursor.y += 20
            }
            cursor.y += 20

            // Category donut
            drawLine(color: colorDivider, strokeWidth: 1)
            cursor.y += 30
            draw("CATEGORY BREAKDOWN", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 30

            let uiChartColors: [UIColor] = Theme.chartColors.map { UIColor($0) }
            let sortedCats = categoryTotals.sorted { $0.value > $1.value }

            if totalSpent > 0 {
                let cx = margin + 70
                let cy = cursor.y + 70
                let radius: CGFloat = 60
                let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                var startAngle: CGFloat = -.pi / 2

                for (i, entry) in sortedCats.prefix(5).enumerated() {
                    let sweep = CGFloat(Double(entry.value) / Double(totalSpent)) * 2 * .pi
                    let path = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: radius,
                                            startAngle: startAngle, endAngle: startAngle + sweep, clockwise: true)
                    uiChartColors[i % uiChartColors.count].setStroke()
                    path.lineWidth = 30
                    path.stroke()
                    startAngle += sweep
                }
                _ = rect

                // Legend
                var legY = cursor.y + 20
                for (i, entry) in sortedCats.prefix(6).enumerated() {
                    if i == 5 {
                        let otherAmt = sortedCats.dropFirst(5).reduce(Int64(0)) { $0 + $1.value }
                        if otherAmt > 0 {
                            drawDot(x: cx + 120, y: legY - 4, color: colorTextSecondary)
                            draw("Other: \(Formatters.formatRupees(otherAmt))", x: cx + 135, size: 12, color: colorTextPrimary, bold: false)
                        }
                    } else {
                        let pct = Int(Double(entry.value) / Double(totalSpent) * 100)
                        drawDot(x: cx + 120, y: legY - 4, color: uiChartColors[i % uiChartColors.count])
                        draw("\(entry.key): \(Formatters.formatRupees(entry.value)) — \(pct)%", x: cx + 135, size: 12, color: colorTextPrimary, bold: false)
                        legY += 24
                    }
                }
            }
            cursor.y += 170

            // Daily spending bars
            if !transactions.isEmpty {
                drawLine(color: colorDivider, strokeWidth: 1)
                cursor.y += 30
                draw("DAILY SPENDING", x: margin, size: 14, color: colorTextPrimary, bold: true)
                cursor.y += 30

                let maxDaily = dailyTotals.values.max() ?? 1
                let chartHeight: CGFloat = 100
                let chartWidth = pageWidth - 2 * margin
                let daysList = Array(dailyTotals.keys.prefix(14))
                let barWidth = min(30, chartWidth / CGFloat(daysList.count + 1))
                let spacing = (chartWidth - CGFloat(daysList.count) * barWidth) / CGFloat(daysList.count + 1)

                var currentX = margin + spacing
                let chartBottomY = cursor.y + chartHeight

                colorDivider.setStroke()
                let axis = UIBezierPath()
                axis.move(to: CGPoint(x: margin, y: chartBottomY))
                axis.addLine(to: CGPoint(x: pageWidth - margin, y: chartBottomY))
                axis.lineWidth = 1
                axis.stroke()

                for dateKey in daysList {
                    let amt = dailyTotals[dateKey] ?? 0
                    let barHeight = CGFloat(Double(amt) / Double(maxDaily)) * chartHeight
                    colorBrand.setFill()
                    UIBezierPath(roundedRect: CGRect(x: currentX, y: chartBottomY - barHeight, width: barWidth, height: barHeight), cornerRadius: 4).fill()
                    let dayStr = dateKey.split(separator: " ").first.map(String.init) ?? dateKey
                    draw(dayStr, x: currentX + barWidth / 2, size: 10, color: colorTextSecondary, bold: false, align: .center)
                    currentX += barWidth + spacing
                }
                cursor.y += chartHeight + 20
            }

            // Payment methods
            draw("PAYMENT METHODS", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25
            let upi = transactions.filter { $0.paymentMethod.lowercased().contains("upi") }.reduce(Int64(0)) { $0 + $1.amountPaise }
            let cash = transactions.filter { $0.paymentMethod.lowercased().contains("cash") }.reduce(Int64(0)) { $0 + $1.amountPaise }
            let upiPct = totalSpent > 0 ? Int(Double(upi) / Double(totalSpent) * 100) : 0
            let cashPct = totalSpent > 0 ? Int(Double(cash) / Double(totalSpent) * 100) : 0

            colorBrand.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: cursor.y, width: 200, height: 40), cornerRadius: 8).fill()
            draw("UPI", x: margin + 16, size: 18, color: .white, bold: true)
            draw("\(Formatters.formatRupees(upi)) (\(upiPct)%)", x: margin + 16, size: 12, color: .white, bold: false)
            cursor.y += 52
            colorSuccess.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: cursor.y, width: 200, height: 40), cornerRadius: 8).fill()
            draw("Cash", x: margin + 16, size: 18, color: .white, bold: true)
            draw("\(Formatters.formatRupees(cash)) (\(cashPct)%)", x: margin + 16, size: 12, color: .white, bold: false)
            cursor.y += 70

            // Largest expenses
            drawLine(color: colorDivider, strokeWidth: 1)
            cursor.y += 30
            draw("LARGEST EXPENSES", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25
            let largestTxs = transactions.filter { $0.type == .expense }.sorted { $0.amountPaise > $1.amountPaise }.prefix(5)
            drawTransactionTable(Array(largestTxs), currentUser: currentUser, partnerUser: partnerUser,
                                 cursor: cursor, pageHeight: pageHeight, margin: margin, pageWidth: pageWidth,
                                 colorBackground: colorBackground, colorTextPrimary: colorTextPrimary,
                                 colorTextSecondary: colorTextSecondary, colorSuccess: colorSuccess,
                                 draw: draw, newPage: { newPage(context: ctx) })

            // Transaction ledger
            drawLine(color: colorDivider, strokeWidth: 1)
            cursor.y += 30
            draw(reportType.lowercased() == "weekly" ? "TRANSACTION DETAILS" : "TRANSACTION LEDGER", x: margin, size: 14, color: colorTextPrimary, bold: true)
            cursor.y += 25
            drawTransactionTable(transactions, currentUser: currentUser, partnerUser: partnerUser,
                                 cursor: cursor, pageHeight: pageHeight, margin: margin, pageWidth: pageWidth,
                                 colorBackground: colorBackground, colorTextPrimary: colorTextPrimary,
                                 colorTextSecondary: colorTextSecondary, colorSuccess: colorSuccess,
                                 draw: draw, newPage: { newPage(context: ctx) })
        }

        let reportsDir = FileManager.default.temporaryDirectory.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        let url = reportsDir.appendingPathComponent("OurMoney_Report_\(Int(Date().timeIntervalSince1970 * 1000)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func drawDot(x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(arcCenter: CGPoint(x: x, y: y), radius: 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true).fill()
    }

    private static func drawTransactionTable(_ txs: [Transaction],
                                             currentUser: User,
                                             partnerUser: User?,
                                             cursor: Cursor,
                                             pageHeight: CGFloat,
                                             margin: CGFloat,
                                             pageWidth: CGFloat,
                                             colorBackground: UIColor,
                                             colorTextPrimary: UIColor,
                                             colorTextSecondary: UIColor,
                                             colorSuccess: UIColor,
                                             draw: (String, CGFloat, CGFloat, UIColor, Bool, NSTextAlignment) -> Void,
                                             newPage: () -> Void) {
        let colDate = margin
        let colCat = margin + 80
        let colDesc = margin + 180
        let colPaid = margin + 300
        let colAmt = pageWidth - margin

        func checkSpace(_ required: CGFloat) {
            if cursor.y + required > pageHeight - margin - 30 {
                newPage()
            }
        }

        // Header
        colorBackground.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: cursor.y - 12, width: pageWidth - margin, height: 20)).fill()
        draw("Date", colDate, 10, colorTextSecondary, true)
        draw("Category", colCat, 10, colorTextSecondary, true)
        draw("Notes", colDesc, 10, colorTextSecondary, true)
        draw("Paid By", colPaid, 10, colorTextSecondary, true)
        draw("Amount", colAmt, 10, colorTextSecondary, true, .right)
        cursor.y += 20

        for (index, tx) in txs.enumerated() {
            checkSpace(24)
            if index % 2 == 1 {
                colorBackground.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: cursor.y - 12, width: pageWidth - margin, height: 24)).fill()
            }
            let dateStr = Formatters.shortDayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(tx.dateMillis) / 1000))
            let catStr = tx.category.count > 15 ? String(tx.category.prefix(13)) + ".." : tx.category
            let notesStr = tx.notes.isEmpty ? "-" : (tx.notes.count > 18 ? String(tx.notes.prefix(16)) + ".." : tx.notes)
            let paidStr = tx.paidBy == currentUser.id ? "You" : (partnerUser?.name ?? "Partner")
            let amtColor: UIColor = tx.type == .expense ? colorTextPrimary : colorSuccess
            draw(dateStr, colDate, 10, colorTextPrimary, false)
            draw(catStr, colCat, 10, colorTextPrimary, false)
            draw(notesStr, colDesc, 10, colorTextPrimary, false)
            draw(paidStr, colPaid, 10, colorTextPrimary, false)
            draw(Formatters.formatRupees(tx.amountPaise), colAmt, 10, amtColor, true, .right)
            cursor.y += 24
        }
        cursor.y += 10
    }
}
