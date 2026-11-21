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
    private let onDeleteAccount: () -> Void
    private let onSignOut: () -> Void
    private let onSavingCompleted: (SavingTransaction, PersonalGoal, Int, Int, [PipoBadge]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthStateManager.self) private var authStateManager
    @Environment(NavigationManager.self) private var navigationManager
    @Query(sort: \PersonalGoal.createdAt, order: .reverse)
    private var goals: [PersonalGoal]
    @Query(sort: \SavingTransaction.date, order: .reverse)
    private var transactions: [SavingTransaction]
    @Query private var profiles: [UserProfile]

    @State private var selectedPage = DashboardPage.home
    @State private var selectedGroupGoal: PersonalGoal?
    @State private var showingAchievements = false
    @State private var showingPrivacyOverview = false
    @State private var mascotReply: String?
    @State private var goalToRecord: PersonalGoal?
    @State private var savingAmount = ""
    @State private var isShowingSaveConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var completedSavingReward: (
        transaction: SavingTransaction,
        goal: PersonalGoal,
        xpEarned: Int,
        streakDays: Int,
        unlockedBadges: [PipoBadge]
    )?

    init(
        onCreateGoal: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void = {},
        onSignOut: @escaping () -> Void = {},
        onSavingCompleted: @escaping (SavingTransaction, PersonalGoal, Int, Int, [PipoBadge]) -> Void = {
            _, _, _, _, _ in
        }
    ) {
        self.onCreateGoal = onCreateGoal
        self.onDeleteAccount = onDeleteAccount
        self.onSignOut = onSignOut
        self.onSavingCompleted = onSavingCompleted
    }

    private var ownedGoals: [PersonalGoal] {
        AccountScope.visibleGoals(goals, userID: authStateManager.userID)
    }

    private var ownedTransactions: [SavingTransaction] {
        AccountScope.visibleTransactions(
            transactions, goals: ownedGoals, userID: authStateManager.userID
        )
    }

    private var activeGoals: [PersonalGoal] {
        ownedGoals.filter(\.canRecordSaving)
    }

    private var pausedGoals: [PersonalGoal] {
        ownedGoals.filter { $0.lifecycleState == .paused }
    }

    private var archivedGoals: [PersonalGoal] {
        ownedGoals.filter { $0.lifecycleState == .archived }
    }

    private var completedGoals: [PersonalGoal] {
        ownedGoals.filter { $0.lifecycleState == .completed }
    }

    private var focusGoal: PersonalGoal? {
        if let pinned = activeGoals.first(where: { $0.isFocusPreferred == true }) {
            return pinned
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

    private var earnedBadgeCount: Int {
        let earned = Set(currentProfile?.unlockedBadgeIds ?? [])
        return PipoBadge.allCases.filter { earned.contains($0.rawValue) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if ownedGoals.isEmpty && selectedPage == .home {
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
            // Account and privacy controls must remain reachable even for
            // newly onboarded users who have not created a saving goal.
            bottomNavigation
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .tint(PipoTheme.deepPink)
        .onAppear {
            updateWidgetSnapshot()
            openPendingDepositRequest()
            if navigationManager.consumeAchievementsRequest() {
                showingAchievements = true
            }
        }
        .onChange(of: navigationManager.isMilestonePresented) { _, isPresented in
            if !isPresented && navigationManager.consumeAchievementsRequest() {
                showingAchievements = true
            }
        }
        .onChange(of: navigationManager.pendingDepositGoalID) { _, goalID in
            guard goalID != nil else { return }
            openPendingDepositRequest()
        }
        .onChange(of: authStateManager.userID) { _, _ in
            // A presented sheet or deferred milestone cannot survive account switches.
            isShowingSaveConfirmation = false
            goalToRecord = nil
            selectedGroupGoal = nil
            showingAchievements = false
            showingPrivacyOverview = false
            completedSavingReward = nil
            mascotReply = nil
            selectedPage = .home
            updateWidgetSnapshot()
        }
        .sheet(isPresented: $isShowingSaveConfirmation, onDismiss: clearPendingSaving) {
            if let goalToRecord,
               AccountScope.owns(goalToRecord, userID: authStateManager.userID),
               goalToRecord.canRecordSaving {
                saveConfirmation
                    .presentationDetents([.medium])
            } else {
                ContentUnavailableView("Goal unavailable", systemImage: "lock.shield")
            }
        }
        .sheet(item: $selectedGroupGoal) { goal in
            if AccountScope.owns(goal, userID: authStateManager.userID) {
                groupGoalDetail(goal)
            } else {
                ContentUnavailableView("Goal unavailable", systemImage: "lock.shield")
            }
        }
        .sheet(isPresented: $showingAchievements) {
            achievementsSheet
        }
        .sheet(isPresented: $showingPrivacyOverview) {
            privacyOverviewSheet
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
                    if !ownedGoals.isEmpty {
                        Text("YOUR SPACE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(PipoTheme.deepPink)
                    }
                    Text(onboardingPersonalization.flatMap { $0.nickname.isEmpty ? nil : "Hey, \($0.nickname)!" } ?? "Pipo")
                        .font(.largeTitle.bold())
                        .foregroundStyle(PipoTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(ownedGoals.isEmpty
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
            if let mascotReply, !ownedGoals.isEmpty {
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

    /// First-time home stays actionable and renders the approved V4 Empty B.
    /// The existing three-step guidance remains visible below the card.
    private var firstGoalWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your first saving goal")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            PipoEmptyStateBCard(onCreate: onCreateGoal)
            Text(firstGoalInvitation)
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
            VStack(alignment: .leading, spacing: 10) {
                firstGoalStep("1", title: "Pick your goal")
                firstGoalStep("2", title: "Set a target and date")
                firstGoalStep("3", title: "Record progress as you save")
            }
            Text("No rush. You can explore Pipo before creating a goal.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
        }
        .accessibilityIdentifier("pipo.home.firstGoal")
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-allcards-qa"),
               let focusGoal {
                PipoApprovedCardsGalleryQA(
                    goal: focusGoal,
                    groupGoal: ownedGoals.first(where: { $0.isGroupGoal }),
                    transactions: logs(for: focusGoal),
                    earnedIDs: Set(currentProfile?.unlockedBadgeIds ?? []),
                    onOpenCollection: { showingAchievements = true },
                    onCreateGoal: onCreateGoal,
                    onSeeJourney: { selectedPage = .journey }
                )
            }
            #endif
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
                        Text(pausedGoals.isEmpty
                             ? "Your active goals are complete or archived. You can start another whenever you're ready."
                             : "Your plans are paused. Resume one from Saving goals when you're ready.")
                            .font(.subheadline)
                            .foregroundStyle(PipoTheme.muted)
                        Button("Create a saving goal", action: onCreateGoal)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }
            }
            if !pausedGoals.isEmpty {
                sectionHeader("Paused for now", action: "See all") {
                    selectedPage = .goals
                }
                ForEach(pausedGoals.prefix(2)) { goal in
                    compactGoalRow(goal)
                }
            }
            if !completedGoals.isEmpty {
                sectionHeader("Goals you reached", action: "See all") {
                    selectedPage = .goals
                }
                ForEach(completedGoals.prefix(2)) { goal in
                    PipoCompletionBCard(goal: goal) {
                        selectedPage = .journey
                    }
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

            focusGoalNavigation(for: goal)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(money(goal.currentAmount, goal: goal))
                        .font(.title2.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text("/ " + money(goal.targetAmount, goal: goal))
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(money(goal.currentAmount, goal: goal)).font(.title2.bold())
                    Text("of " + money(goal.targetAmount, goal: goal)).font(.footnote)
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
                Text("\(money(goal.remainingAmount, goal: goal)) left")
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
                    value: "\(earnedBadgeCount) badges",
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
        let count = SavingConsistency.consecutivePeriods(
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

    /// A value-based NavigationLink participates directly in RootView's
    /// NavigationStack instead of relying on an imperative path mutation.
    /// Group goals retain their distinct local detail sheet.
    @ViewBuilder
    private func focusGoalNavigation(for goal: PersonalGoal) -> some View {
        if goal.isGroupGoal {
            Button {
                openGoal(goal)
            } label: {
                focusGoalNavigationLabel(for: goal)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pipo.dashboard.focusGoal")
            .accessibilityLabel(focusGoalAccessibilitySummary(for: goal))
            .accessibilityHint("Opens goal details")
        } else {
            NavigationLink(value: Route.personalGoal(goal.id)) {
                focusGoalNavigationLabel(for: goal)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pipo.dashboard.focusGoal")
            .accessibilityLabel(focusGoalAccessibilitySummary(for: goal))
            .accessibilityHint("Opens goal details")
        }
    }

    /// The featured goal is a separate action from Record a saving.
    /// VoiceOver needs the same account-owned status and manually recorded
    /// progress context that sighted users can read in the card.
    private func focusGoalAccessibilitySummary(for goal: PersonalGoal) -> String {
        let progressPercent = Int(goal.progress * 100)
        return "\(goal.title), \(goal.isGroupGoal ? "group" : "personal") saving goal, " +
            "\(goal.lifecycleState.title), \(money(goal.currentAmount, goal: goal)) recorded, " +
            "\(progressPercent) percent complete"
    }

    private func focusGoalNavigationLabel(for goal: PersonalGoal) -> some View {
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
        .contentShape(Rectangle())
    }

    private func compactGoalRow(_ goal: PersonalGoal) -> some View {
        Button {
            openGoal(goal)
        } label: {
            compactGoalRowLabel(goal)
        }
        .buttonStyle(.plain)
        .contextMenu {
            goalLifecycleMenu(goal)
        }
        .accessibilityIdentifier("pipo.dashboard.goal.\(goal.id.uuidString)")
        .accessibilityLabel(
            "\(goal.title), \(goal.isGroupGoal ? "group" : "personal") saving goal, " +
            "\(goal.lifecycleState.title), \(money(goal.currentAmount, goal: goal)) recorded, " +
            "\(Int(goal.progress * 100)) percent complete"
        )
        .accessibilityHint("Opens goal details. More actions are available.")
        // VoiceOver users must not need to discover a long-press context menu.
        // Keep these actions identical to the existing lifecycle menu.
        .accessibilityActions {
            if goal.canRecordSaving {
                Button("Make focus goal") { makeFocusGoal(goal) }
                Button("Pause goal") { changeLifecycle(of: goal, to: .paused) }
            }
            if goal.lifecycleState == .paused || goal.lifecycleState == .archived {
                Button("Resume goal") { changeLifecycle(of: goal, to: .active) }
            }
            if goal.lifecycleState == .active || goal.lifecycleState == .paused {
                Button("Archive goal") { changeLifecycle(of: goal, to: .archived) }
            }
        }
    }

    private func compactGoalRowLabel(_ goal: PersonalGoal) -> some View {
        let kind = goal.isGroupGoal ? "Group" : "Personal"
        let subtitle = "\(kind) · \(goal.lifecycleState.title) · \(money(goal.currentAmount, goal: goal)) recorded"
        let percentage = Int(goal.progress * 100)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(PipoTheme.ink)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PipoTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(percentage)%")
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

    @ViewBuilder
    private func goalLifecycleMenu(_ goal: PersonalGoal) -> some View {
        if goal.canRecordSaving {
            Button("Make focus goal", systemImage: "pin.fill") {
                makeFocusGoal(goal)
            }
            Button("Pause goal", systemImage: "pause.circle") {
                changeLifecycle(of: goal, to: .paused)
            }
        }
        if goal.lifecycleState == .paused || goal.lifecycleState == .archived {
            Button("Resume goal", systemImage: "play.circle") {
                changeLifecycle(of: goal, to: .active)
            }
        }
        if goal.lifecycleState == .active || goal.lifecycleState == .paused {
            Button("Archive goal", systemImage: "archivebox") {
                changeLifecycle(of: goal, to: .archived)
            }
        }
    }

    private func makeFocusGoal(_ goal: PersonalGoal) {
        guard AccountScope.owns(goal, userID: authStateManager.userID),
              goal.canRecordSaving else { return }
        let previous = ownedGoals.map { (goal: $0, flag: $0.isFocusPreferred) }
        for owned in ownedGoals { owned.isFocusPreferred = owned.id == goal.id }
        do {
            try modelContext.save()
            selectedPage = .home
            updateWidgetSnapshot()
        } catch {
            for old in previous { old.goal.isFocusPreferred = old.flag }
            saveErrorMessage = "Couldn't keep your focus goal. Please try again."
        }
    }

    private func changeLifecycle(of goal: PersonalGoal, to state: GoalLifecycleState) {
        guard AccountScope.owns(goal, userID: authStateManager.userID) else { return }
        let previous = goal.lifecycleRaw
        guard goal.transition(to: state) else { return }
        do {
            try modelContext.save()
            if !goal.canRecordSaving, goalToRecord?.id == goal.id {
                goalToRecord = nil
                isShowingSaveConfirmation = false
            }
            updateWidgetSnapshot()
        } catch {
            goal.lifecycleRaw = previous
            saveErrorMessage = "Couldn't update this goal. Please try again."
        }
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
            if !pausedGoals.isEmpty {
                Text("PAUSED").font(.caption.bold()).foregroundStyle(PipoTheme.muted)
                    .padding(.top, 10)
                ForEach(pausedGoals) { goal in compactGoalRow(goal) }
            }
            if !archivedGoals.isEmpty {
                Text("ARCHIVED").font(.caption.bold()).foregroundStyle(PipoTheme.muted)
                    .padding(.top, 10)
                ForEach(archivedGoals) { goal in compactGoalRow(goal) }
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
            PipoMilestonesDCard(
                earnedIDs: Set(currentProfile?.unlockedBadgeIds ?? []),
                onOpenCollection: { showingAchievements = true }
            )
            Text("RECENT ACTIVITY")
                .font(.caption.bold())
                .foregroundStyle(PipoTheme.muted)
            PipoActivityHistoryDCard(
                transactions: ownedTransactions,
                titleForGoal: { goalID in
                    ownedGoals.first(where: { $0.id == goalID })?.title ?? "Saving entry"
                }
            )
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
            Divider()
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                Text("Account & privacy")
                    .font(.headline)
                    .foregroundStyle(PipoTheme.ink)
                Text("Deleting your Pipo account permanently removes your saved goals, saving history and profile. This does not move or withdraw money.")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.muted)
                Button { showingPrivacyOverview = true } label: {
                    Label("Your data & privacy", systemImage: "hand.raised")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("pipo.profile.privacyInformation")
                Button(action: onSignOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("pipo.profile.signOut")
                Button(role: .destructive, action: onDeleteAccount) {
                    Label("Delete my account", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("pipo.profile.deleteAccount")
            }
        }
    }

    // In-app transparency is useful while the final public legal policy is
    // being verified. This summary is not a replacement for the App Store
    // privacy policy URL and must match the actual shipped SDK inventory.
    private var privacyOverviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your data in Pipo")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Pipo helps you record your own savings. Pipo doesn't hold, move, or check real money.")
                        .foregroundStyle(PipoTheme.ink)
                    Text("What's saved")
                        .font(.headline)
                    Text("Your iPhone keeps your goals, contributions, progress, achievements, and optional personalization. Pipo may upload your personal goals and their entries to your account on Supabase. Group plans are device-local; a full cloud restore isn't available yet.")
                        .foregroundStyle(PipoTheme.muted)
                    Text("Your account")
                        .font(.headline)
                    Text("Email sign-in uses Supabase authentication. You can sign out or delete your account from Profile → Account & privacy. Deletion asks for explicit confirmation.")
                        .foregroundStyle(PipoTheme.muted)
                    Text("Before publishing")
                        .font(.headline)
                    Text("The full privacy policy and verified support information will be published before Pipo's App Store release.")
                        .foregroundStyle(PipoTheme.muted)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Privacy overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingPrivacyOverview = false }
                        .accessibilityIdentifier("pipo.privacy.done")
                }
            }
        }
    }

    private var achievementsSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("\(earnedBadgeCount) of \(PipoBadge.allCases.count) badges collected")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                        .accessibilityIdentifier("pipo.achievements.count")
                    ForEach(PipoBadge.allCases) { badge in
                        let earned = currentProfile?.unlockedBadgeIds.contains(badge.rawValue) ?? false
                        HStack(spacing: 12) {
                            Image("PipoBadge_\(badge.rawValue)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 76, height: 68)
                                .opacity(earned ? 1 : 0.35)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(badge.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(PipoTheme.ink)
                                Text(badge.description)
                                    .font(.caption)
                                    .foregroundStyle(PipoTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(earned ? "Earned" : (badge.isImplemented ? "Locked" : "Coming later"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(earned ? PipoTheme.deepPink : PipoTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: earned ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(earned ? PipoTheme.deepPink : PipoTheme.muted)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(earned ? PipoTheme.palePink : PipoTheme.cream,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(badge.title). \(earned ? "Earned" : badge.isImplemented ? "Locked" : "Coming later"). \(badge.description)")
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
                    PipoPlanOverviewBCard(
                        goal: goal,
                        preparedMembers: goal.groupDetails.flatMap {
                            try? JSONDecoder().decode(GroupPlanDetails.self, from: $0)
                        }?.preparedMembers ?? []
                    )
                    LabeledContent("Status", value: goal.lifecycleState.title)
                    LabeledContent("Target date", value: goal.targetDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                    Text("This screen shows recorded goal progress, not verified contributions from individual members.")
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.muted)
                    if goal.canRecordSaving {
                        Button("Pause group goal") {
                            changeLifecycle(of: goal, to: .paused)
                        }
                        .accessibilityIdentifier("pipo.goal.pause")
                    } else if goal.lifecycleState == .paused || goal.lifecycleState == .archived {
                        Button("Resume group goal") {
                            changeLifecycle(of: goal, to: .active)
                        }
                        .accessibilityIdentifier("pipo.goal.resume")
                    }
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
        guard AccountScope.owns(goal, userID: authStateManager.userID) else { return }
        if goal.isGroupGoal {
            selectedGroupGoal = goal
        } else {
            navigationManager.navigate(to: .personalGoal(goal.id))
        }
    }

    private func beginRecording(_ goal: PersonalGoal) {
        guard AccountScope.owns(goal, userID: authStateManager.userID),
              goal.canRecordSaving else { return }
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

    private func money(_ amount: Double, goal: PersonalGoal) -> String {
        PipoGoalCurrency.display(amount, code: goal.effectiveCurrencyCode,
            exactMinor: amount == goal.targetAmount ? goal.exactTargetMinor :
                amount == goal.currentAmount ? goal.exactRecordedMinor : nil)
    }

    private func money(_ amount: Double) -> String {
        "Rp" + amount.formatted(
            .number.precision(.fractionLength(0)).locale(Locale(identifier: "id_ID"))
        )
    }

    private func logs(for goal: PersonalGoal) -> [SavingTransaction] {
        guard AccountScope.owns(goal, userID: authStateManager.userID) else { return [] }
        return ownedTransactions.filter { $0.goalId == goal.id }
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
                    TextField("Amount in " + (goalToRecord?.effectiveCurrencyCode ?? "IDR"), text: $savingAmount)
                        .accessibilityIdentifier("pipo.currency.recordSavingAmount")
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
                    .disabled(parsedSavingAmount == nil || goalToRecord?.canRecordSaving != true)
                }
            }
        }
    }

    private var parsedSavingMinor: Int64? {
        guard let goalToRecord else { return nil }
        return PipoGoalCurrency.parseMinor(
            savingAmount, code: goalToRecord.effectiveCurrencyCode
        )
    }

    private var parsedSavingAmount: Double? {
        guard let goalToRecord, let minor = parsedSavingMinor else { return nil }
        return NSDecimalNumber(decimal:
            PipoGoalCurrency.decimal(minor, code: goalToRecord.effectiveCurrencyCode)
        ).doubleValue
    }

    private func confirmSaving() {
        guard let goal = goalToRecord,
              let userID = authStateManager.userID,
              authStateManager.authState == .authenticated,
              AccountScope.owns(goal, userID: userID),
              goal.canRecordSaving,
              let amount = parsedSavingAmount,
              let exactMinor = parsedSavingMinor,
              let oldExactMinor = goal.exactRecordedMinor,
              exactMinor > 0 else {
            isShowingSaveConfirmation = false
            return
        }

        let existingProfile = UserProfile.existing(for: userID, in: profiles)
        let profile = existingProfile ?? UserProfile(userID: userID)
        let previousCurrentAmount = goal.currentAmount
        let previousRecordedMinorUnits = goal.recordedMinorUnits
        let (nextMinorUnits, minorOverflow) = oldExactMinor.addingReportingOverflow(exactMinor)
        guard !minorOverflow,
              nextMinorUnits >= 0,
              PipoGoalCurrency.decimal(nextMinorUnits, code: goal.effectiveCurrencyCode)
                <= PipoGoalCurrency.serverMaximum
        else {
            saveErrorMessage = "This amount would exceed the supported goal limit."
            isShowingSaveConfirmation = false
            return
        }
        let previousTotalXP = profile.totalXP
        let previousCurrentLevel = profile.currentLevel
        let previousStreakDays = profile.streakDays
        let previousLastSavingDate = profile.lastSavingDate
        let previousUserID = profile.userID
        let previousBadges = profile.unlockedBadgeIds
        let priorGoalTransactions = logs(for: goal)
        let transaction: SavingTransaction
        let newlyUnlocked: [PipoBadge]

        do {
            profile.userID = userID
            transaction = try GamificationManager().recordSaving(
                amount: amount,
                goal: goal,
                profile: profile,
                priorTransactions: priorGoalTransactions
            )
            transaction.userID = userID
            transaction.currencyCode = goal.effectiveCurrencyCode
            transaction.amountMinorUnits = exactMinor
            goal.recordedMinorUnits = nextMinorUnits
            goal.currentAmount = NSDecimalNumber(decimal:
                PipoGoalCurrency.decimal(nextMinorUnits, code: goal.effectiveCurrencyCode)
            ).doubleValue
            newlyUnlocked = AchievementEngine.grant(
                profile: profile, goal: goal, transaction: transaction,
                history: ownedTransactions, previousAmount: previousCurrentAmount
            )
        } catch {
            profile.userID = previousUserID
            goal.currentAmount = previousCurrentAmount
            goal.recordedMinorUnits = previousRecordedMinorUnits
            profile.totalXP = previousTotalXP
            profile.currentLevel = previousCurrentLevel
            profile.streakDays = previousStreakDays
            profile.lastSavingDate = previousLastSavingDate
            profile.unlockedBadgeIds = previousBadges
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
            goal.recordedMinorUnits = previousRecordedMinorUnits
            profile.totalXP = previousTotalXP
            profile.currentLevel = previousCurrentLevel
            profile.streakDays = previousStreakDays
            profile.lastSavingDate = previousLastSavingDate
            profile.unlockedBadgeIds = previousBadges
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
            profile.streakDays,
            newlyUnlocked
        )
        updateWidgetSnapshot(latestTransaction: transaction)
        isShowingSaveConfirmation = false
    }

    private func openPendingDepositRequest() {
        guard let goalID = navigationManager.consumeDepositRequest() else { return }
        guard let goal = ownedGoals.first(where: {
            $0.id == goalID && !$0.isGroupGoal && $0.canRecordSaving
        }) else {
            saveErrorMessage = "That personal goal is no longer active."
            return
        }

        goalToRecord = goal
        savingAmount = ""
        isShowingSaveConfirmation = true
    }

    private func updateWidgetSnapshot(latestTransaction: SavingTransaction? = nil) {
        guard let userID = authStateManager.userID else { return }
        let profile = currentProfile
        let goal = (focusGoal?.isGroupGoal == false ? focusGoal : nil)
            ?? activeGoals.first(where: { !$0.isGroupGoal })
        let widgetHistory: [SavingTransaction] = goal.map { goal in
            var history = logs(for: goal)
            if let latestTransaction,
               latestTransaction.userID == userID,
               latestTransaction.goalId == goal.id,
               !history.contains(where: { $0.id == latestTransaction.id }) {
                // @Query can publish after the save callback; include it once now.
                history.append(latestTransaction)
            }
            return history
        } ?? []
        let lastSavingDate = widgetHistory.map(\.date).max()

        let snapshot = WidgetSnapshot(
            streakDays: goal.map {
                SavingConsistency.consecutivePeriods(
                    dates: widgetHistory.map(\.date),
                    rhythm: $0.rhythm, startDate: $0.startDate
                )
            } ?? 0,
            totalXP: profile?.totalXP ?? 0,
            currentLevel: profile?.currentLevel ?? 1,
            goalID: goal?.id,
            goalTitle: goal?.title,
            goalProgress: goal?.progress ?? 0,
            nextDepositDate: goal.flatMap {
                nextDepositDate(for: $0, lastSavingDate: lastSavingDate)
            },
            ownerUserID: userID,
            consistencyUnit: goal.flatMap { goal in
                switch goal.rhythm {
                case .daily: "day"
                case .weekly: "week"
                case .biWeekly: "2-week period"
                case .monthly: "month"
                case .flexible: nil
                }
            },
            recordedCount: widgetHistory.count
        )

        do {
            try WidgetSharedData.activate(userID: userID)
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
        if let reward = completedSavingReward,
           reward.transaction.userID == authStateManager.userID,
           AccountScope.owns(reward.goal, userID: authStateManager.userID) {
            onSavingCompleted(
                reward.transaction,
                reward.goal,
                reward.xpEarned,
                reward.streakDays,
                reward.unlockedBadges
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


// Compatibility entry point; one canonical cadence implementation.
enum DashboardActivity {
    static func consecutivePeriods(
        dates: [Date], rhythm: SavingRhythm, startDate: Date,
        asOf now: Date = .now, calendar: Calendar = .current
    ) -> Int {
        SavingConsistency.consecutivePeriods(
            dates: dates, rhythm: rhythm, startDate: startDate,
            asOf: now, calendar: calendar
        )
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
        guard goal.canRecordSaving, goal.rhythm != .flexible,
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
