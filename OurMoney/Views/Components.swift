import SwiftUI

/// Subtle animated gradient background (port of ui/components/AnimatedBackground.kt).
struct AnimatedBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [Theme.tealContainer.opacity(0.35), OMColor.background(.dark)],
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animateGradient)
        .onAppear { animateGradient = true }
    }
}

// MARK: - Charts

struct DonutChart: View {
    let data: [(String, Int64)]
    let total: Int64

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(OMColor.surfaceVariant(.dark), lineWidth: 18)
                if total > 0 {
                    ForEach(Array(chartSlices.enumerated()), id: \.offset) { index, slice in
                        Circle()
                            .trim(from: slice.start, to: slice.end)
                            .stroke(Theme.chartColors[index % Theme.chartColors.count],
                                    style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                }
                Text(total > 0 ? Formatters.formatRupees(total) : "₹0")
                    .font(.headline)
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(data.prefix(5).enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.chartColors[index % Theme.chartColors.count])
                            .frame(width: 10, height: 10)
                        Text(entry.0)
                            .font(.footnote)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((Double(entry.1) / Double(max(1, total))) * 100))%")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if data.isEmpty {
                    Text("No expenses yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var chartSlices: [(start: Double, end: Double)] {
        guard total > 0 else { return [] }
        var slices: [(Double, Double)] = []
        var running = 0.0
        for entry in data.prefix(5) {
            let fraction = Double(entry.1) / Double(total)
            slices.append((running, running + fraction))
            running += fraction
        }
        return slices
    }
}

struct WeeklyBarChart: View {
    let data: [WeeklyDayStat]

    var body: some View {
        let maxSpent = data.map(\.spentPaise).max() ?? 1
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(day.spentPaise > 0 ? Theme.teal : OMColor.surfaceVariant(.dark))
                        .frame(height: max(6, CGFloat(Double(day.spentPaise) / Double(max(1, maxSpent))) * 90))
                    Text(day.dayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Cards

struct StatCard: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint == .primary ? Color.primary : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Transaction row (shared by Dashboard + History)

struct TransactionRow: View {
    let transaction: Transaction
    let currentUserId: String
    let partnerName: String
    var isSettlement: Bool = false
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSettlement ? Theme.success.opacity(0.2) : Theme.teal.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: isSettlement ? "arrow.left.arrow.right" : categoryIcon)
                    .foregroundStyle(isSettlement ? Theme.success : Theme.teal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(isSettlement ? "Settlement" : transaction.category)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !transaction.notes.isEmpty {
                    Text(transaction.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if transaction.isPending || (isSettlement && transaction.isPending) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(paidByText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.formatRupees(transaction.amountPaise))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(transaction.type == .income ? Theme.success : Color.primary)
                Text(Formatters.shortDayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(transaction.dateMillis) / 1000)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var categoryIcon: String {
        switch transaction.category {
        case "Food & Dining": return "fork.knife"
        case "Groceries": return "cart"
        case "Transport": return "bus"
        case "Shopping": return "bag"
        case "Entertainment": return "tv"
        case "Bills & Utilities": return "doc.text"
        case "Health": return "cross.case"
        case "Travel": return "airplane"
        case "Education": return "book"
        case "Settlement": return "arrow.left.arrow.right"
        default: return "creditcard"
        }
    }

    private var paidByText: String {
        if isSettlement {
            return transaction.paidBy == currentUserId ? "Paid by you" : "Paid by \(partnerName)"
        }
        return transaction.paidBy == currentUserId ? "You paid" : "\(partnerName) paid"
    }
}
