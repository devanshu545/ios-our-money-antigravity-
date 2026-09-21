import Foundation

enum Formatters {
    /// Matches Android `formatRupees(paise)`: `₹120` when whole, `₹120.50` otherwise.
    static func formatRupees(_ paise: Int64) -> String {
        let rupees = Double(paise) / 100.0
        if rupees.truncatingRemainder(dividingBy: 1.0) == 0.0 {
            return "₹\(Int64(rupees))"
        }
        return String(format: "₹%.2f", rupees)
    }

    /// Android's `(tx.amountPaise / 100.0).toString().removeSuffix(".0")` used in edit fields.
    static func plainAmountString(_ paise: Int64) -> String {
        let rupees = Double(paise) / 100.0
        if rupees.truncatingRemainder(dividingBy: 1.0) == 0.0 {
            return "\(Int64(rupees))"
        }
        return "\(rupees)"
    }

    /// Parses a rupee amount string into paise (supports "600", "600.5", "600.50").
    static func parseRupeesToPaise(_ text: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return Int64((value * 100.0).rounded())
    }

    static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/yyyy"
        return f
    }()

    static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static func monthYearString(from date: Date) -> String {
        monthYearFormatter.string(from: date)
    }
}
