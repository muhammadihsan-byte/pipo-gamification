import SwiftData
import SwiftUI

@MainActor
struct ReviewPlanView: View {
    let plan: PersonalGoalPlan
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(AuthStateManager.self) private var authStateManager
    @Query private var goals: [PersonalGoal]
    @Query private var profiles: [UserProfile]

    @State private var isPaywallPresented = false
    @State private var isCreatingGoal = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Goal") {
                LabeledContent("Name", value: plan.title)
                LabeledContent("Category", value: plan.category.rawValue.capitalized)
                LabeledContent(
                    "Target",
                    value: plan.targetAmount.formatted(.currency(code: "IDR").precision(.fractionLength(0)))
                )
            }

            if !plan.breakdown.isEmpty {
                Section("Target breakdown") {
                    ForEach(plan.breakdown) { item in
                        LabeledContent(
                            item.title,
                            value: parsedBreakdownAmount(item.amount)?
                                .formatted(.currency(code: "IDR").precision(.fractionLength(0))) ?? "—"
                        )
                    }
                }
            }

            Section("Timeline and rhythm") {
                LabeledContent("Start", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Target date", value: plan.targetDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Saving rhythm", value: plan.rhythm.rawValue.capitalized)
                LabeledContent("Duration", value: "\(durationInMonths) months")
            }

            Section {
                Button("Confirm and create goal", action: confirmCreation)
                    .disabled(isCreatingGoal)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Review plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Edit") { dismiss() }
            }
        }
        .onAppear(perform: syncEntitlements)
        .onChange(of: currentProfile?.purchasedPersonalSlots) { _, _ in
            syncEntitlements()
        }
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView(isGroup: false)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Unable to create goal",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var durationInMonths: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: plan.startDate)
        let target = calendar.startOfDay(for: plan.targetDate)
        let months = calendar.dateComponents([.month], from: start, to: target).month ?? 0
        guard
            let anniversary = calendar.date(byAdding: .month, value: months, to: start),
            anniversary < target
        else {
            return months
        }
        return months + 1
    }

    private var activePersonalGoalCount: Int {
        goals.filter { !$0.isGroupGoal }.count
    }

    private var currentProfile: UserProfile? {
        UserProfile.existing(for: authStateManager.userID, in: profiles)
    }

    private func confirmCreation() {
        guard !isCreatingGoal else { return }
        guard subscriptionManager.canCreateGoal(
            isGroup: false,
            activeCount: activePersonalGoalCount
        ) else {
            isPaywallPresented = true
            return
        }

        isCreatingGoal = true
        defer { isCreatingGoal = false }
        let existingProfile = currentProfile
        let profile = existingProfile ?? UserProfile(userID: authStateManager.userID)
        let previousCount = profile.activePersonalGoalsCount
        let previousUserID = profile.userID
        let goal = PersonalGoal(
            title: plan.title,
            category: plan.category,
            targetAmount: plan.targetAmount,
            startDate: plan.startDate,
            targetDate: plan.targetDate,
            rhythm: plan.rhythm
        )
        goal.subItems = plan.breakdown.compactMap { item in
            guard let amount = parsedBreakdownAmount(item.amount) else { return nil }
            return SubItem(title: item.title, amount: amount)
        }

        profile.userID = authStateManager.userID
        profile.activePersonalGoalsCount = activePersonalGoalCount + 1
        modelContext.insert(goal)
        if existingProfile == nil {
            modelContext.insert(profile)
        }

        do {
            try modelContext.save()
            onCreated()
        } catch {
            modelContext.delete(goal)
            profile.userID = previousUserID
            profile.activePersonalGoalsCount = previousCount
            if existingProfile == nil {
                modelContext.delete(profile)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func syncEntitlements() {
        let profile = currentProfile
        subscriptionManager.updateEntitlements(
            purchasedPersonalSlots: profile?.purchasedPersonalSlots ?? 0,
            purchasedGroupSlots: profile?.purchasedGroupSlots ?? 0
        )
    }

    private func parsedBreakdownAmount(_ value: String) -> Double? {
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
