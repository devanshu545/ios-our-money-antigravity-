import SwiftUI

/// Mirror of `ui/analytics/AnalyticsScreen.kt`, rendered with native SwiftUI charts.
struct AnalyticsView: View {
    let user: User
    let household: Household

    @StateObject private var viewModel: AnalyticsViewModel
    @State private var partnerName = "Friend"

    init(user: User, household: Household) {
        self.user = user
        self.household = household
        _viewModel = StateObject(wrappedValue: AnalyticsViewModel(currentUser: user, household: household))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        DonutChart(data: viewModel.stats.categoryBreakdown,
                                   total: viewModel.stats.totalSpent)

                        HStack(spacing: 12) {
                            StatCard(title: "You Paid", value: Formatters.formatRupees(viewModel.stats.youPaid))
                            StatCard(title: "\(partnerName) Paid", value: Formatters.formatRupees(viewModel.stats.partnerPaid))
                        }

                        HStack(spacing: 12) {
                            StatCard(title: "UPI", value: Formatters.formatRupees(viewModel.stats.upiSpent), tint: Theme.brandBlue)
                            StatCard(title: "Cash", value: Formatters.formatRupees(viewModel.stats.cashSpent), tint: Theme.success)
                        }

                        if let highest = viewModel.stats.highestTransaction {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Highest transaction")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(highest.category) — \(Formatters.formatRupees(highest.amountPaise))")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }

                        if viewModel.stats.categoryBreakdown.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.pie")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Add expenses to see analytics")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 24)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let partnerId = household.members.first { $0 != user.id } ?? ""
                if !partnerId.isEmpty, let partner = await UserRepository().getUserSuspend(partnerId) {
                    partnerName = partner.name.isEmpty ? "Friend" : partner.name
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
