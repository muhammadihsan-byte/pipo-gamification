import SwiftData
import SwiftUI

struct GoalBreakdownDraft: Identifiable {
    let id: UUID
    var title: String
    var amount: String

    init(id: UUID = UUID(), title: String = "", amount: String = "") {
        self.id = id
        self.title = title
        self.amount = amount
    }
}

struct PersonalGoalPlan {
    let title: String
    let category: GoalCategory
    let targetAmount: Double
    let breakdown: [GoalBreakdownDraft]
    let startDate: Date
    let targetDate: Date
    let rhythm: SavingRhythm
}

@MainActor
struct CreateGoalView: View {
    @State private var title = ""
    @State private var targetAmount = ""
    @State private var category: GoalCategory = .gadget
    @State private var rhythm: SavingRhythm = .monthly
    @State private var startDate: Date
    @State private var targetDate: Date
    @State private var breakdown = [GoalBreakdownDraft()]

    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        let start = Calendar.current.startOfDay(for: .now)
        let target = Calendar.current.date(byAdding: .month, value: 2, to: start)
            ?? start.addingTimeInterval(60 * 60 * 24 * 60)
        _startDate = State(initialValue: start)
        _targetDate = State(initialValue: target)
        self.onBack = onBack
    }

    var body: some View {
        Form {
            Section("Goal") {
                TextField("Goal name", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(GoalCategory.allCases) { category in
                        Text(category.rawValue.capitalized)
                            .tag(category)
                    }
                }
                TextField("Target amount in IDR", text: $targetAmount)
                    .keyboardType(.decimalPad)
            }

            Section {
                ForEach($breakdown) { $item in
                    HStack {
                        TextField("Item", text: $item.title)
                        TextField("Amount", text: $item.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .onDelete { breakdown.remove(atOffsets: $0) }
                Button("Add breakdown item", systemImage: "plus") {
                    breakdown.append(GoalBreakdownDraft())
                }
            } header: {
                Text("Target breakdown")
            } footer: {
                Text("Add optional items to help plan your target.")
            }

            Section("Timeline") {
                DatePicker(
                    "Start date",
                    selection: $startDate,
                    in: ...targetDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "Target date",
                    selection: $targetDate,
                    in: startDate...,
                    displayedComponents: .date
                )
            }

            Section("Saving rhythm") {
                Picker("Frequency", selection: $rhythm) {
                    ForEach(SavingRhythm.allCases) { rhythm in
                        Text(rhythm.rawValue.capitalized)
                            .tag(rhythm)
                    }
                }
            }
        }
        .navigationTitle("Create a goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onBack)
            }
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink {
                    if let goalPlan {
                        ReviewPlanView(
                            plan: goalPlan,
                            onBack: onBack,
                            onCreated: onBack
                        )
                    } else {
                        EmptyView()
                    }
                } label: {
                    Text("Review")
                }
                .disabled(goalPlan == nil)
            }
        }
    }

    private var goalPlan: PersonalGoalPlan? {
        guard
            let amount = parseAmount(targetAmount),
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            targetDate > startDate,
            breakdown.allSatisfy({ item in
                item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && item.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && parseAmount(item.amount) != nil
            })
        else {
            return nil
        }

        let completedBreakdown = breakdown.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return PersonalGoalPlan(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            targetAmount: amount,
            breakdown: completedBreakdown,
            startDate: startDate,
            targetDate: targetDate,
            rhythm: rhythm
        )
    }

    private func parseAmount(_ value: String) -> Double? {
        guard
            let amount = Double(
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
            ),
            amount.isFinite,
            amount > 0
        else {
            return nil
        }
        return amount
    }
}

#Preview {
    NavigationStack {
        CreateGoalView(onBack: {})
    }
}
