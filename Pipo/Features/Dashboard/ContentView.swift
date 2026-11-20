import SwiftData
import SwiftUI
import WidgetKit

private enum DashboardPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case goals = "Goals"
    case journey = "Journey"
    case profile = "Profile"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .goals: "target"
        case .journey: "chart.bar.xaxis"
        case .profile: "person.crop.circle"
        }
    }
}

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

    @State private var selectedPage = DashboardPage.home
    @State private var preferredFocusGoalID: UUID?
    @State private var selectedGroupGoal: PersonalGoal?
    @State private var showingAchievements = false
    @State private var mascotReply: String?
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

    init(
        onCreateGoal: @escaping () -> Void,
        onSavingCompleted: @escaping (SavingTransaction, PersonalGoal, Int, Int) -> Void = {
            _, _, _, _ in
        }
    ) {
        self.onCreateGoal = onCreateGoal
        self.onSavingCompleted = onSavingCompleted
    }

    private var activeGoals: [PersonalGoal] {
        goals.filter { $0.progress < 1 }
    }

    private var completedGoals: [PersonalGoal] {
        goals.filter { $0.progress >= 1 }
    }

    private var focusGoal: PersonalGoal? {
        if let preferredFocusGoalID,
           let match = activeGoals.first(where: { $0.id == preferredFocusGoalID }) {
            return match
        }
        let personal = activeGoals.filter { !$0.isGroupGoal }
        // The most advanced active personal goal has priority over newer drafts.
        // Group goals are considered when no personal goal remains active.
        return (personal.isEmpty ? activeGoals : personal)
            .max { lhs, rhs in
                lhs.progress == rhs.progress
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.progress < rhs.progress
            }
    }

    private var otherGoals: [PersonalGoal] {
        activeGoals.filter { $0.id != focusGoal?.id }
    }

    private var currentProfile: UserProfile? {
        UserProfile.existing(for: authStateManager.userID, in: profiles)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if goals.isEmpty {
                        welcomeHeader
                        firstGoalWelcomeCard
                    } else {
                        switch selectedPage {
                        case .home:
                            welcomeHeader
                            homeDashboard
                        case .goals:
                            pageHeading("Saving goals", subtitle: "Every goal has its own pace.")
                            goalsPage
                        case .journey:
                            pageHeading("Your journey", subtitle: "The progress you've recorded.")
                            journeyPage
                        case .profile:
                            pageHeading("Your space", subtitle: "A little overview of your Pipo account.")
                            profilePage
                        }
                    }
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            if !goals.isEmpty {
                bottomNavigation
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .tint(PipoTheme.deepPink)
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
            mascotReply = nil
        }
        .sheet(isPresented: $isShowingSaveConfirmation, onDismiss: clearPendingSaving) {
            saveConfirmation
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedGroupGoal) { goal in
            groupGoalDetail(goal)
        }
        .sheet(isPresented: $showingAchievements) {
            achievementsSheet
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

    private var onboardingPersonalization: OnboardingPersonalization? {
        guard let userID = authStateManager.userID else { return nil }
        return OnboardingProfileStore.load(for: userID)
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if !goals.isEmpty {
                        Text("YOUR SPACE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(PipoTheme.deepPink)
                    }
                    Text(onboardingPersonalization.flatMap { $0.nickname.isEmpty ? nil : "Hey, \($0.nickname)!" } ?? "Pipo")
                        .font(.largeTitle.bold())
                        .foregroundStyle(PipoTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(goals.isEmpty
                        ? (onboardingPersonalization?.motivation?.homeGreeting ?? "Little by little, it adds up.")
                        : "Your plans, your pace.")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                }
                Spacer(minLength: 4)
                PipoMascotView(
                    companion: .idle,
                    isPresented: !isShowingSaveConfirmation
                        && !navigationManager.isMilestonePresented
                        && saveErrorMessage == nil,
                    onTap: {
                        mascotReply = mascotReply == nil ? "Small steps count, too." : nil
                    }
                )
                .frame(width: 97, height: 105)
                .accessibilityIdentifier("pipo.dashboard.mascot")
            }
            if let mascotReply, !goals.isEmpty {
                HStack(spacing: 8) {
                    Text(mascotReply)
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Button("Dismiss") { self.mascotReply = nil }
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(PipoTheme.ink)
                .padding(12)
                .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("pipo.dashboard.mascotReply")
            }
        }
    }

    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold()).foregroundStyle(PipoTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(PipoTheme.muted)
        }
        .padding(.vertical, 10)
    }

    private var firstGoalInvitation: String {
        switch onboardingPersonalization?.motivation {
        case .buildHabit:
            "Small steps start here."
        case .excitingGoal:
            "Big idea? Give it a place to grow."
        case .feelInControl:
            "Your plan, your pace."
        case .exploring:
            "Just looking around? That's fine too."
        case nil:
            "Whatever you're planning, start when you're ready."
        }
    }

    /// The first Home state should teach the actual goal journey without
    /// forcing a goal, showing fabricated progress, or duplicating the CTA.
    private var firstGoalWelcomeCard: some View {
        TicketCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(PipoTheme.pink)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your first saving goal")
                            .font(.headline)
                            .foregroundStyle(PipoTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(firstGoalInvitation)
                            .font(.subheadline)
                            .foregroundStyle(PipoTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Choose something that matters, set a target, then record what you save.")
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                TicketSeparator()

                VStack(alignment: .leading, spacing: 10) {
                    firstGoalStep("1", title: "Pick your goal")
                    firstGoalStep("2", title: "Set a target and date")
                    firstGoalStep("3", title: "Record progress as you save")
                }
                .accessibilityElement(children: .contain)

                Button("Create a saving goal", action: onCreateGoal)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("pipo.home.firstGoal.create")

                Text("No rush. You can explore Pipo before creating a goal.")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func firstGoalStep(_ number: String, title: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(PipoTheme.deepPink)
                .frame(width: 26, height: 26)
                .background(PipoTheme.palePink, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PipoTheme.ink)
        }
        .accessibilityElement(children: .combine)
    }


    private var homeDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let focusGoal {
                featuredGoalCard(focusGoal)
                activityAndAchievements(for: focusGoal)
                sectionHeader("Other saving goals", action: otherGoals.isEmpty ? nil : "See all") {
                    selectedPage = .goals
                }
                if otherGoals.isEmpty {
                    Text("Your next goal can wait. Keep enjoying this one.")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                } else {
                    ForEach(otherGoals) { goal in
                        compactGoalRow(goal)
                    }
                }
                insightCard(for: focusGoal)
            } else {
                TicketCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Every goal has its moment.")
                            .font(.title3.bold())
                        Text("Your existing goals are complete. You can start another whenever you're ready.")
                            .font(.subheadline)
                            .foregroundStyle(PipoTheme.muted)
                        Button("Create a saving goal", action: onCreateGoal)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }
            }
            if !completedGoals.isEmpty {
                sectionHeader("Goals you reached", action: "See all") {
                    selectedPage = .goals
                }
                ForEach(completedGoals.prefix(2)) { goal in
                    compactGoalRow(goal)
                }
            }
            if focusGoal != nil {
                Button("Create a saving goal", action: onCreateGoal)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.deepPink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("pipo.dashboard.createGoal")
            }
        }
    }

    private func featuredGoalCard(_ goal: PersonalGoal) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("FOCUS GOAL")
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(PipoTheme.deepPink)
                Spacer()
                Text(goal.isGroupGoal ? "GROUP" : rhythmTag(goal.rhythm))
                    .font(.caption2.bold())
                    .foregroundStyle(PipoTheme.deepPink)
            }

            Button {
                openGoal(goal)
            } label: {
                HStack {
                    Text(goal.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(PipoTheme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(PipoTheme.deepPink)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pipo.dashboard.focusGoal")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(money(goal.currentAmount))
                        .font(.title2.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text("/ " + money(goal.targetAmount))
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(money(goal.currentAmount)).font(.title2.bold())
                    Text("of " + money(goal.targetAmount)).font(.footnote)
                }
                .foregroundStyle(PipoTheme.ink)
            }

            ProgressView(value: goal.progress)
                .tint(PipoTheme.pink)
                .accessibilityLabel("Saving goal progress")
                .accessibilityValue("\(Int(goal.progress * 100)) percent")

            HStack {
                Text("\(Int(goal.progress * 100))% complete")
                    .foregroundStyle(PipoTheme.deepPink)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text("\(money(goal.remainingAmount)) left")
                    .foregroundStyle(PipoTheme.muted)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(goal.rhythm == .flexible ? "YOUR PACE" : "NEXT PLANNED")
                            .font(.caption2.bold())
                            .foregroundStyle(PipoTheme.muted)
                        if goal.rhythm == .flexible {
                            Text("Save when you can")
                                .font(.subheadline.weight(.semibold))
                        } else if let next = nextDepositDate(for: goal, lastSavingDate: nil) {
                            Text(next.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("Review your plan")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 6)
                    if let amount = plannedAmount(for: goal) {
                        Text(money(amount))
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.trailing)
                    }
                }
                .foregroundStyle(PipoTheme.ink)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))

            Button("Record a saving") {
                beginRecording(goal)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("pipo.dashboard.recordSaving")

            Text(goal.isGroupGoal
                 ? "Shared progress is recorded manually, not bank-verified."
                 : "Recorded by you, not a verified bank balance.")
                .font(.caption2)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 24))
        // Individual actions provide their own accessibility identifiers.
    }

    private func activityAndAchievements(for goal: PersonalGoal) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedPage = .journey
            } label: {
                metricCard(
                    label: goal.rhythm == .flexible ? "YOUR PACE" : "YOUR RHYTHM",
                    value: rhythmValue(for: goal),
                    hint: goal.rhythm == .flexible
                        ? "No streak required"
                        : "Recorded saving periods"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pipo.dashboard.rhythm")

            Button {
                showingAchievements = true
            } label: {
                metricCard(
                    label: "ACHIEVEMENTS",
                    value: "\(currentProfile?.unlockedBadgeIds.count ?? 0) badges",
                    hint: "See your collection"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pipo.dashboard.achievements")
        }
        .frame(maxWidth: .infinity)
    }

    private func metricCard(label: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(PipoTheme.muted)
                .lineLimit(2)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(PipoTheme.ink)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 106, alignment: .topLeading)
        .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func rhythmValue(for goal: PersonalGoal) -> String {
        let count = DashboardActivity.consecutivePeriods(
            dates: logs(for: goal).map(\.date),
            rhythm: goal.rhythm,
            startDate: goal.startDate
        )
        if goal.rhythm == .flexible {
            let n = logs(for: goal).count
            return "\(n) \(n == 1 ? "save" : "saves")"
        }
        let unit: String
        switch goal.rhythm {
        case .daily: unit = count == 1 ? "day" : "days"
        case .weekly: unit = count == 1 ? "week" : "weeks"
        case .biWeekly: unit = count == 1 ? "period" : "periods"
        case .monthly: unit = count == 1 ? "month" : "months"
        case .flexible: unit = "saves"
        }
        return "\(count) \(unit)"
    }

    private func sectionHeader(_ title: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(PipoTheme.ink)
            Spacer(minLength: 4)
            if let action {
                Button(action, action: perform)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.deepPink)
                    .frame(minHeight: 44)
            }
        }
    }

    private func compactGoalRow(_ goal: PersonalGoal) -> some View {
        Button {
            openGoal(goal)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(PipoTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text((goal.isGroupGoal ? "Group" : "Personal") + " · " + money(goal.currentAmount) + " recorded")
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int(goal.progress * 100))%")
                        .font(.headline.bold())
                        .foregroundStyle(PipoTheme.deepPink)
                    Text("View goal")
                        .font(.caption2)
                        .foregroundStyle(PipoTheme.muted)
                }
            }
            .padding(14)
            .frame(minHeight: 80)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(PipoTheme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if goal.progress < 1 {
                Button("Make focus goal", systemImage: "pin.fill") {
                    preferredFocusGoalID = goal.id
                    selectedPage = .home
                }
            }
        }
        .accessibilityIdentifier("pipo.dashboard.goal.\(goal.id.uuidString)")
        .accessibilityHint("Opens goal details")
    }

    private func insightCard(for goal: PersonalGoal) -> some View {
        let count = logs(for: goal).filter {
            Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
        }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("A LITTLE INSIGHT")
                    .font(.caption2.bold())
                    .tracking(0.5)
                    .foregroundStyle(PipoTheme.deepPink)
                Spacer(minLength: 8)
                Text("Based on your logs")
                    .font(.caption2)
                    .foregroundStyle(PipoTheme.muted)
            }
            Text(count > 0 ? "You recorded \(count) \(count == 1 ? "save" : "saves") this month." : "Your plan is ready when you are.")
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.ink)
            Text(count > 0
                 ? "Each contribution you record moves \(goal.title) forward."
                 : "No pressure. Record progress whenever you save.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(PipoTheme.border))
        .accessibilityIdentifier("pipo.dashboard.insight")
    }

    private var goalsPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            Button("Create a saving goal", action: onCreateGoal)
                .buttonStyle(PrimaryActionButtonStyle())
            if !activeGoals.isEmpty {
                Text("IN PROGRESS").font(.caption.bold()).foregroundStyle(PipoTheme.muted)
                ForEach(activeGoals) { goal in compactGoalRow(goal) }
            }
            if !completedGoals.isEmpty {
                Text("COMPLETED").font(.caption.bold()).foregroundStyle(PipoTheme.muted)
                    .padding(.top, 10)
                ForEach(completedGoals) { goal in compactGoalRow(goal) }
            }
        }
    }

    private var journeyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showingAchievements = true
            } label: {
                HStack {
                    Label("Achievements", systemImage: "medal.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(currentProfile?.unlockedBadgeIds.count ?? 0) earned")
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(PipoTheme.ink)
                .padding(16)
                .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("pipo.dashboard.journey.achievements")
            Text("RECENT ACTIVITY")
                .font(.caption.bold())
                .foregroundStyle(PipoTheme.muted)
            if transactions.isEmpty {
                Text("No contributions recorded yet. Your journey starts when you save.")
                    .foregroundStyle(PipoTheme.muted)
                    .font(.subheadline)
            } else {
                ForEach(transactions.prefix(20)) { transaction in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goals.first(where: { $0.id == transaction.goalId })?.title ?? "Saving entry")
                                .font(.subheadline.bold())
                            Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(PipoTheme.muted)
                        }
                        Spacer()
                        Text("+ " + money(transaction.amount))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PipoTheme.deepPink)
                    }
                    .padding(14)
                    .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Text("Entries are self-reported and are not bank transactions.")
                .font(.caption)
                .foregroundStyle(PipoTheme.muted)
        }
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            TicketCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(onboardingPersonalization?.nickname.isEmpty == false
                         ? (onboardingPersonalization?.nickname ?? "")
                         : "Your Pipo profile")
                        .font(.title3.bold())
                    LabeledContent("Active goals", value: "\(activeGoals.count)")
                    LabeledContent("Completed goals", value: "\(completedGoals.count)")
                    HStack {
                        Text("Total XP")
                            .accessibilityIdentifier("pipo.dashboard.profile.xpLabel")
                        Spacer()
                        Text("\(currentProfile?.totalXP ?? 0)")
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Level", value: "\(currentProfile?.currentLevel ?? 1)")
                }
                .font(.subheadline)
            }
            Text("Pipo doesn't move money. Your savings are recorded by you.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
        }
    }

    private var achievementsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let ids = currentProfile?.unlockedBadgeIds, !ids.isEmpty {
                        ForEach(ids, id: \.self) { id in
                            Label(id.replacingOccurrences(of: "-", with: " ").capitalized, systemImage: "medal.fill")
                                .font(.headline)
                                .foregroundStyle(PipoTheme.deepPink)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        ContentUnavailableView(
                            "No badges yet",
                            systemImage: "medal",
                            description: Text("Your first achievement comes from a real saving milestone.")
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingAchievements = false }
                }
            }
        }
    }

    private func groupGoalDetail(_ goal: PersonalGoal) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(goal.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Group saving · manually recorded progress")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                    TicketCard {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Recorded", value: money(goal.currentAmount))
                            ProgressView(value: goal.progress)
                                .tint(PipoTheme.pink)
                                .accessibilityLabel("Shared goal progress")
                                .accessibilityValue("\(Int(goal.progress * 100)) percent")
                            LabeledContent("Target", value: money(goal.targetAmount))
                            LabeledContent("Remaining", value: money(goal.remainingAmount))
                            LabeledContent("Target date", value: goal.targetDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    Text("This screen shows recorded goal progress, not verified contributions from individual members.")
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.muted)
                }
                .padding(20)
            }
            .navigationTitle("Group goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedGroupGoal = nil }
                }
            }
        }
    }

    private func openGoal(_ goal: PersonalGoal) {
        if goal.isGroupGoal {
            selectedGroupGoal = goal
        } else {
            navigationManager.navigate(to: .personalGoal(goal.id))
        }
    }

    private func beginRecording(_ goal: PersonalGoal) {
        guard goal.progress < 1 else { return }
        goalToRecord = goal
        savingAmount = ""
        isShowingSaveConfirmation = true
    }

    private func rhythmTag(_ rhythm: SavingRhythm) -> String {
        switch rhythm {
        case .daily: "DAILY"
        case .weekly: "WEEKLY"
        case .biWeekly: "EVERY 2 WEEKS"
        case .monthly: "MONTHLY"
        case .flexible: "FLEXIBLE"
        }
    }

    private func money(_ amount: Double) -> String {
        "Rp" + amount.formatted(
            .number.precision(.fractionLength(0)).locale(Locale(identifier: "id_ID"))
        )
    }

    private func logs(for goal: PersonalGoal) -> [SavingTransaction] {
        transactions.filter {
            $0.goalId == goal.id
            && (authStateManager.userID == nil
                || $0.userID == authStateManager.userID || $0.userID == nil)
        }
    }

    private func plannedAmount(for goal: PersonalGoal) -> Double? {
        guard goal.rhythm != .flexible else { return nil }
        if let amount = goal.plannedContributionOverride, amount > 0 {
            return Double(amount)
        }
        guard !goal.isGroupGoal, goal.targetAmount.isFinite,
              goal.targetAmount >= 1, goal.targetAmount < Double(Int.max) else { return nil }
        return PersonalSavingSchedule(
            targetAmount: Int(goal.targetAmount),
            startDate: goal.startDate,
            targetDate: goal.targetDate,
            rhythm: goal.rhythm,
            preferredDay: goal.preferredSavingDay
        ).map { Double($0.amount) }
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(DashboardPage.allCases) { page in
                Button {
                    selectedPage = page
                    mascotReply = nil
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Text(page.rawValue)
                            .font(.caption2.weight(selectedPage == page ? .bold : .medium))
                    }
                    .foregroundStyle(selectedPage == page ? PipoTheme.deepPink : PipoTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                .accessibilityIdentifier("pipo.dashboard.tab.\(page.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.white)
        .overlay(alignment: .top) {
            Rectangle().fill(PipoTheme.border).frame(height: 1)
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
        guard let next = DashboardSchedule.nextDate(for: goal, asOf: .now) else { return nil }
        // A contribution on the scheduled day counts for that planned period.
        // Extra early contributions do not silently move the selected weekday.
        if let lastSavingDate, Calendar.current.isDate(lastSavingDate, inSameDayAs: next) {
            let followingDay = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? next
            return DashboardSchedule.nextDate(for: goal, asOf: followingDay)
        }
        return next
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


// A goal-specific streak represents periods containing recorded contributions.
// Unlike UserProfile.streakDays, it never combines goals with different rhythms.
enum DashboardActivity {
    static func consecutivePeriods(
        dates: [Date],
        rhythm: SavingRhythm,
        startDate: Date,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard rhythm != .flexible else { return 0 }
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        guard start <= today else { return 0 }
        let currentPeriod = index(for: today, from: start, rhythm: rhythm, calendar: calendar)
        let savedPeriods = Set(dates.compactMap { date -> Int? in
            guard date >= startDate, date <= now else { return nil }
            return index(for: date, from: start, rhythm: rhythm, calendar: calendar)
        })
        guard let mostRecent = savedPeriods.max(),
              mostRecent >= currentPeriod - 1 else { return 0 }
        var count = 0
        var period = mostRecent
        while savedPeriods.contains(period) {
            count += 1
            period -= 1
        }
        return count
    }

    private static func index(
        for date: Date,
        from start: Date,
        rhythm: SavingRhythm,
        calendar: Calendar
    ) -> Int {
        switch rhythm {
        case .daily:
            return calendar.dateComponents([.day], from: start, to: date).day ?? 0
        case .weekly, .biWeekly:
            let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            return days / (rhythm == .weekly ? 7 : 14)
        case .monthly:
            let startMonth = calendar.dateInterval(of: .month, for: start)?.start ?? start
            let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
            return calendar.dateComponents([.month], from: startMonth, to: currentMonth).month ?? 0
        case .flexible:
            return 0
        }
    }
}


/// A date derived from the user's selected saving rhythm and preferred day,
/// not from the date of the last (possibly extra) contribution.
enum DashboardSchedule {
    static func nextDate(
        for goal: PersonalGoal,
        asOf now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard goal.progress < 1, goal.rhythm != .flexible,
              goal.targetAmount.isFinite,
              goal.targetAmount >= 1,
              goal.targetAmount < Double(Int.max),
              let schedule = PersonalSavingSchedule(
                  targetAmount: Int(goal.targetAmount),
                  startDate: goal.startDate,
                  targetDate: goal.targetDate,
                  rhythm: goal.rhythm,
                  preferredDay: goal.preferredSavingDay,
                  calendar: calendar
              )
        else { return nil }

        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: schedule.firstDate)
        if first >= today { return first }

        let next: Date?
        switch goal.rhythm {
        case .daily, .weekly, .biWeekly:
            let step = goal.rhythm == .daily ? 1 : (goal.rhythm == .weekly ? 7 : 14)
            let passedDays = calendar.dateComponents([.day], from: first, to: today).day ?? 0
            let periodsAhead = (passedDays + step - 1) / step
            next = calendar.date(byAdding: .day, value: periodsAhead * step, to: first)
        case .monthly:
            guard let firstMonth = calendar.dateInterval(of: .month, for: first)?.start,
                  let todayMonth = calendar.dateInterval(of: .month, for: today)?.start
            else { return nil }
            let elapsed = max(0, calendar.dateComponents([.month], from: firstMonth, to: todayMonth).month ?? 0)
            let preferred = goal.preferredSavingDay ?? calendar.component(.day, from: goal.startDate)
            func candidate(inMonth offset: Int) -> Date? {
                guard let month = calendar.date(byAdding: .month, value: offset, to: firstMonth),
                      let days = calendar.range(of: .day, in: .month, for: month)
                else { return nil }
                return calendar.date(byAdding: .day, value: min(preferred, days.count) - 1, to: month)
            }
            let thisMonth = candidate(inMonth: elapsed)
            next = (thisMonth ?? first) >= today ? thisMonth : candidate(inMonth: elapsed + 1)
        case .flexible:
            return nil
        }
        guard let next, next <= schedule.lastDate else { return nil }
        return next
    }
}
