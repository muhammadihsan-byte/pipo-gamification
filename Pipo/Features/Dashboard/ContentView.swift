import SwiftData
import SwiftUI
import WidgetKit

@MainActor
struct DashboardView: View {
    private let onCreateGoal: () -> Void
    private let onSavingCompleted: (SavingTransaction, PersonalGoal, Int, Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthStateManager.self) private var authStateManager
    @Environment(NavigationManager.self) private var navigationManager
    @Query(sort: \PersonalGoal.createdAt, order: .reverse)
    private var goals: [PersonalGoal]
    @Query(sort: \SavingTransaction.date, order: .reverse)
    private var transactions: [SavingTransaction]
    @Query private var profiles: [UserProfile]

    @State private var goalToRecord: PersonalGoal?
    @State private var savingAmount = ""
    @State private var isShowingSaveConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var completedSavingReward: (
        transaction: SavingTransaction,
        goal: PersonalGoal,
        xpEarned: Int,
        streakDays: Int
    )?
    @State private var mascotState: PipoMascotState = .idle

    init(
        onCreateGoal: @escaping () -> Void,
        onSavingCompleted: @escaping (SavingTransaction, PersonalGoal, Int, Int) -> Void = {
            _, _, _, _ in
        }
    ) {
        self.onCreateGoal = onCreateGoal
        self.onSavingCompleted = onSavingCompleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                welcomeHeader
                savingsSummary

                VStack(alignment: .leading, spacing: 12) {
                    Text("Tujuan tabungan")
                        .font(.title3.bold())
                        .foregroundStyle(PipoTheme.ink)

                    if goals.isEmpty {
                        emptyGoalsCard
                    } else {
                        ForEach(goals) { goal in
                            goalCard(goal)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .tint(PipoTheme.green)
        .onAppear {
            updateWidgetSnapshot()
            openPendingDepositRequest()
        }
        .onChange(of: navigationManager.pendingDepositGoalID) { _, goalID in
            guard goalID != nil else { return }
            openPendingDepositRequest()
        }
        .onChange(of: authStateManager.userID) { _, _ in
            updateWidgetSnapshot()
        }
        .sheet(isPresented: $isShowingSaveConfirmation, onDismiss: clearPendingSaving) {
            saveConfirmation
                .presentationDetents([.medium])
        }
        .alert(
            "Pipo",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var welcomeHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pipo")
                    .font(.largeTitle.bold())
                    .foregroundStyle(PipoTheme.ink)
                Text("Sedikit demi sedikit, jadi bukit.")
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.muted)
            }
            Spacer(minLength: 0)
            PipoMascotView(state: mascotState)
                .frame(width: 100, height: 100)
        }
        .padding(.top, 12)
    }

    private var savingsSummary: some View {
        TicketCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("MULAI PERJALANANMU")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(PipoTheme.green)
                Text("Setiap tabungan membawamu lebih dekat ke tujuan.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                Button("Create a saving goal", action: onCreateGoal)
                    .buttonStyle(PrimaryActionButtonStyle())
            }
        }
    }

    private var emptyGoalsCard: some View {
        TicketCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Belum ada tujuan")
                    .font(.headline)
                    .foregroundStyle(PipoTheme.ink)
                Text("Tujuan pertamamu akan muncul di sini.")
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.muted)
                Text("Create a goal before recording a saving.")
                    .font(.caption)
                    .foregroundStyle(PipoTheme.muted)
            }
        }
    }

    private func goalCard(_ goal: PersonalGoal) -> some View {
        TicketCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if goal.isGroupGoal {
                        Text(goal.title)
                            .font(.headline)
                            .foregroundStyle(PipoTheme.ink)
                    } else {
                        Button(goal.title) { navigationManager.navigate(to: .personalGoal(goal.id)) }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(PipoTheme.ink)
                            .accessibilityHint("Opens the saving goal")
                    }
                    Spacer()
                    Text(goal.categoryTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PipoTheme.green)
                }

                ProgressView(value: goal.progress)
                    .tint(PipoTheme.green)

                HStack {
                    Text(goal.currentAmount, format: .currency(code: "IDR").precision(.fractionLength(0)))
                    Spacer()
                    Text(goal.targetAmount, format: .currency(code: "IDR").precision(.fractionLength(0)))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(PipoTheme.muted)

                Button("Record a saving") {
                    goalToRecord = goal
                    savingAmount = ""
                    isShowingSaveConfirmation = true
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
    }

    private var saveConfirmation: some View {
        NavigationStack {
            Form {
                if let goalToRecord {
                    Section("Goal") {
                        Text(goalToRecord.title)
                    }
                }

                Section("Deposit") {
                    TextField("Amount in IDR", text: $savingAmount)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Record a saving")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingSaveConfirmation = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        confirmSaving()
                    }
                    .disabled(parsedSavingAmount == nil || goalToRecord == nil)
                }
            }
        }
    }

    private var parsedSavingAmount: Double? {
        guard
            let amount = Double(
                savingAmount
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

    private func confirmSaving() {
        guard let goal = goalToRecord, let amount = parsedSavingAmount else { return }

        let existingProfile = UserProfile.existing(for: authStateManager.userID, in: profiles)
        let profile = existingProfile ?? UserProfile(userID: authStateManager.userID)
        let previousCurrentAmount = goal.currentAmount
        let previousTotalXP = profile.totalXP
        let previousCurrentLevel = profile.currentLevel
        let previousStreakDays = profile.streakDays
        let previousLastSavingDate = profile.lastSavingDate
        let previousUserID = profile.userID
        let transaction: SavingTransaction

        do {
            profile.userID = authStateManager.userID
            transaction = try GamificationManager().recordSaving(
                amount: amount,
                goal: goal,
                profile: profile
            )
            transaction.userID = authStateManager.userID
        } catch {
            profile.userID = previousUserID
            goal.currentAmount = previousCurrentAmount
            profile.totalXP = previousTotalXP
            profile.currentLevel = previousCurrentLevel
            profile.streakDays = previousStreakDays
            profile.lastSavingDate = previousLastSavingDate
            saveErrorMessage = error.localizedDescription
            isShowingSaveConfirmation = false
            return
        }

        if existingProfile == nil {
            modelContext.insert(profile)
        }
        modelContext.insert(transaction)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(transaction)
            profile.userID = previousUserID
            goal.currentAmount = previousCurrentAmount
            profile.totalXP = previousTotalXP
            profile.currentLevel = previousCurrentLevel
            profile.streakDays = previousStreakDays
            profile.lastSavingDate = previousLastSavingDate
            if existingProfile == nil {
                modelContext.delete(profile)
            }
            saveErrorMessage = error.localizedDescription
            isShowingSaveConfirmation = false
            return
        }

        mascotState = .happy
        completedSavingReward = (
            transaction,
            goal,
            transaction.xpEarned,
            profile.streakDays
        )
        updateWidgetSnapshot(latestTransaction: transaction)
        isShowingSaveConfirmation = false
    }

    private func openPendingDepositRequest() {
        guard let goalID = navigationManager.consumeDepositRequest() else { return }
        guard let goal = goals.first(where: {
            $0.id == goalID && !$0.isGroupGoal && $0.currentAmount < $0.targetAmount
        }) else {
            saveErrorMessage = "That personal goal is no longer active."
            return
        }

        goalToRecord = goal
        savingAmount = ""
        isShowingSaveConfirmation = true
    }

    private func updateWidgetSnapshot(latestTransaction: SavingTransaction? = nil) {
        let profile = UserProfile.existing(for: authStateManager.userID, in: profiles)
        let goal = goals.first {
            !$0.isGroupGoal && $0.currentAmount < $0.targetAmount
        }
        let lastSavingDate = goal.flatMap { goal in
            [
                latestTransaction.flatMap { $0.goalId == goal.id ? $0 : nil },
                transactions.first(where: { $0.goalId == goal.id })
            ]
                .compactMap { $0?.date }
                .max()
        }

        let snapshot = WidgetSnapshot(
            streakDays: profile?.streakDays ?? 0,
            totalXP: profile?.totalXP ?? 0,
            currentLevel: profile?.currentLevel ?? 1,
            goalID: goal?.id,
            goalTitle: goal?.title,
            goalProgress: goal?.progress ?? 0,
            nextDepositDate: goal.flatMap {
                nextDepositDate(for: $0, lastSavingDate: lastSavingDate)
            }
        )

        do {
            try WidgetSharedData.save(snapshot)
        } catch {
            saveErrorMessage = "The saving was recorded, but the widget could not update: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func nextDepositDate(for goal: PersonalGoal, lastSavingDate: Date?) -> Date? {
        let cadence: (component: Calendar.Component, value: Int)
        switch goal.rhythm {
        case .daily:
            cadence = (.day, 1)
        case .weekly:
            cadence = (.day, 7)
        case .biWeekly:
            cadence = (.day, 14)
        case .monthly:
            cadence = (.month, 1)
        case .flexible:
            return nil
        }

        let calendar = Calendar.current
        var nextDate: Date
        if let lastSavingDate {
            guard let date = calendar.date(
                byAdding: cadence.component,
                value: cadence.value,
                to: lastSavingDate
            ) else {
                return nil
            }
            nextDate = date
        } else {
            nextDate = goal.startDate
        }

        let today = calendar.startOfDay(for: .now)
        while nextDate < today {
            guard let date = calendar.date(
                byAdding: cadence.component,
                value: cadence.value,
                to: nextDate
            ) else {
                return nil
            }
            nextDate = date
        }

        return nextDate <= goal.targetDate ? nextDate : nil
    }

    private func clearPendingSaving() {
        if let reward = completedSavingReward {
            onSavingCompleted(
                reward.transaction,
                reward.goal,
                reward.xpEarned,
                reward.streakDays
            )
            completedSavingReward = nil
        }
        goalToRecord = nil
        savingAmount = ""
    }
}

#Preview {
    NavigationStack {
        DashboardView(onCreateGoal: {})
    }
    .environment(AuthStateManager())
    .environment(NavigationManager())
    .modelContainer(
        for: [PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self],
        inMemory: true
    )
}
