import SwiftData
import SwiftUI

@MainActor
struct ReviewPlanView: View {
    let plan: PersonalGoalPlan
    let onBack: () -> Void
    let onEdit: (PersonalPlanStep) -> Void
    let onCreated: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(AuthStateManager.self) private var authStateManager
    @Query private var goals: [PersonalGoal]
    @Query private var profiles: [UserProfile]

    @State private var saving = false
    @State private var createdGoalID: UUID?
    @State private var isPaywallPresented = false
    @State private var errorMessage: String?

    var body: some View {
        PersonalPlanPage(step: .review, onBack: onBack) {
            PersonalPlanIntro(step: .review, title: "Review your saving plan", subtitle: "Check the details for \(plan.title).")
            goalCard
            if !plan.breakdown.isEmpty {
                budgetBreakdownCard
            }
            timelineCard
            rhythmCard
            Text("This plan is an estimate. Pipo doesn’t move money or set up automatic payments.")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
        } footer: {
            PersonalPlanActions(back: onBack, title: saving ? "Saving…" : "Start saving plan",
                                dimmed: saving, action: { saving = true })
        }
        .disabled(saving || createdGoalID != nil)
        .task(id: saving) {
            if saving { confirmCreation() }
        }
        .accessibilityHidden(createdGoalID != nil)
        .overlay {
            if let createdGoalID {
                confirmation(goalID: createdGoalID)
            }
        }
        .onAppear(perform: syncEntitlements)
        .onChange(of: currentProfile?.purchasedPersonalSlots) { _, _ in syncEntitlements() }
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView(isGroup: false)
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn’t save your plan", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: plan.category == .gadget ? "ipad" : "target")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(PersonalPlanStyle.berry)
                    .frame(width: 44, height: 44)
                    .background(PersonalPlanStyle.blush, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.headline)
                    Text("\(plan.categoryTitle) · Draft")
                        .font(.caption)
                        .foregroundStyle(PersonalPlanStyle.muted)
                }
                Spacer(minLength: 8)
                editButton("goal", step: .goal)
            }

            Divider()
            HStack {
                Text("Target amount")
                    .font(.subheadline.bold())
                Spacer(minLength: 12)
                editButton("target", step: .target)
            }
            Text(money(plan.targetAmount))
                .font(.title3.bold())
                .foregroundStyle(PersonalPlanStyle.berry)
                .accessibilityIdentifier("pipo.review.targetAmount")
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(PersonalPlanStyle.blush, lineWidth: 1.5) }
    }

    // Reuses the exact Budget Breakdown B family also used by goal details.
    // It is read-only: editing still routes through the existing target step.
    private var budgetBreakdownCard: some View {
        PipoBudgetBreakdownCard(
            lines: plan.breakdown.map { item in
                PipoBudgetLine(
                    id: item.id,
                    title: item.cleanTitle,
                    amount: Double(item.rupiah ?? -1)
                )
            },
            targetAmount: plan.targetAmount,
            onEdit: { onEdit(.target) }
        )
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading("Target date", step: .timeline)
            Text(dateLabel(plan.targetDate)).font(.subheadline.bold())
            Text("A date to aim for, not a guaranteed finish.")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeading("Saving rhythm", step: .rhythm)
            summaryRow("Frequency", value: PersonalPlanFormatting.rhythmLabel(plan.rhythm, day: plan.preferredSavingDay))
            if let schedule = plan.schedule {
                summaryRow("Planned amount", value: money(plan.contributionOverride ?? schedule.amount))
                summaryRow("First planned save", value: dateLabel(schedule.firstDate))
                Text(scheduleDetails(schedule, override: plan.contributionOverride))
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
            } else {
                Text("Save whenever you can, with no set amount.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func confirmation(goalID: UUID) -> some View {
        PersonalPlanDialog {
            PipoMascotView(companion: .celebration)
                .frame(width: 94, height: 99)
                .accessibilityHidden(true)

            Text("Your plan is ready!")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Pipo is cheering you on. Take it one save at a time.")
                .font(.footnote)
                .foregroundStyle(PersonalPlanStyle.muted)

            VStack(alignment: .leading, spacing: 8) {
                Label(plan.title, systemImage: "ticket")
                    .font(.subheadline.bold())
                Text(money(plan.targetAmount))
                    .font(.title3.bold())
                    .foregroundStyle(PersonalPlanStyle.berry)
                if let schedule = plan.schedule {
                    Text(money(plan.contributionOverride ?? schedule.amount) + plan.rhythm.unitLabel)
                    Text("First planned save: \(dateLabel(schedule.firstDate))")
                } else {
                    Text("Flexible · save when you can")
                }
            }
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(PersonalPlanStyle.blush, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(PersonalPlanStyle.pink.opacity(0.35)) }

            Button("Done") { onCreated(goalID) }
                .buttonStyle(PersonalPlanPrimaryStyle())
                .accessibilityHint("Opens your new saving goal")
        }
    }

    private func cardHeading(_ title: String, step: PersonalPlanStep) -> some View {
        HStack {
            Text(title).font(.subheadline.bold())
            Spacer(minLength: 8)
            editButton(title.lowercased(), step: step)
        }
    }

    private func editButton(_ field: String, step: PersonalPlanStep) -> some View {
        Button { onEdit(step) } label: { Text("Edit").frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(PersonalPlanStyle.berry)
            .accessibilityLabel("Edit \(field)")
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(PersonalPlanStyle.muted)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private var activePersonalGoalCount: Int {
        AccountScope.visibleGoals(goals, userID: authStateManager.userID)
            .filter { !$0.isGroupGoal && $0.progress < 1 }.count
    }

    private var currentProfile: UserProfile? {
        UserProfile.existing(for: authStateManager.userID, in: profiles)
    }

    private func confirmCreation() {
        defer { saving = false }
        guard createdGoalID == nil else { return }
        guard let userID = authStateManager.userID else {
            errorMessage = "Sign in to create a saving goal."
            return
        }
        let activeCount = activePersonalGoalCount
        guard subscriptionManager.canCreateGoal(isGroup: false, activeCount: activeCount) else {
            isPaywallPresented = true
            return
        }

        let existingProfile = currentProfile
        let profile = existingProfile ?? UserProfile(userID: userID)
        let previousCount = profile.activePersonalGoalsCount
        let previousUserID = profile.userID
        let goal = PersonalGoal(
            title: plan.title, category: plan.category, customCategory: plan.customCategory,
            targetAmount: plan.targetAmount, startDate: plan.startDate, targetDate: plan.targetDate,
            rhythm: plan.rhythm, preferredSavingDay: plan.preferredSavingDay,
            ownerUserID: userID
        )
        goal.plannedContributionOverride = plan.contributionOverride
        goal.subItems = plan.breakdown.compactMap { item in
            guard let amount = item.rupiah else { return nil }
            return SubItem(title: item.cleanTitle, amount: Double(amount))
        }

        profile.userID = userID
        profile.activePersonalGoalsCount = activeCount + 1
        modelContext.insert(goal)
        if existingProfile == nil { modelContext.insert(profile) }

        do {
            try modelContext.save()
            createdGoalID = goal.id
        } catch {
            modelContext.delete(goal)
            if existingProfile == nil {
                modelContext.delete(profile)
            } else {
                profile.userID = previousUserID
                profile.activePersonalGoalsCount = previousCount
            }
            errorMessage = "Your plan wasn’t saved. Please try again."
        }
    }

    private func syncEntitlements() {
        subscriptionManager.updateEntitlements(
            purchasedPersonalSlots: currentProfile?.purchasedPersonalSlots ?? 0,
            purchasedGroupSlots: currentProfile?.purchasedGroupSlots ?? 0
        )
    }
}

struct PersonalPlanDialog<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16, content: content)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: 342)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { Color.black.opacity(0.52).ignoresSafeArea() }
        .foregroundStyle(PersonalPlanStyle.ink)
        .accessibilityAddTraits(.isModal)
    }
}

@MainActor
struct PersonalGoalDetailView: View {
    private let onBack: () -> Void
    private let recordSaving: () -> Void

    @Query private var goals: [PersonalGoal]
    @Environment(AuthStateManager.self) private var authStateManager
    @Environment(\.modelContext) private var modelContext
    @State private var lifecycleError: String?

    init(goalID: UUID, onBack: @escaping () -> Void, recordSaving: @escaping () -> Void) {
        _goals = Query(filter: #Predicate<PersonalGoal> { $0.id == goalID })
        self.onBack = onBack
        self.recordSaving = recordSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onBack) {
                    Label("Saving goals", systemImage: "chevron.left")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(PipoTheme.ink)

                if let goal = goals.first,
                   AccountScope.owns(goal, userID: authStateManager.userID) {
                    details(for: goal)
                } else {
                    ContentUnavailableView("Goal unavailable", systemImage: "target")
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(.white)
        .foregroundStyle(PipoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Goal not updated", isPresented: Binding(
            get: { lifecycleError != nil },
            set: { if !$0 { lifecycleError = nil } }
        )) {
            Button("OK", role: .cancel) { lifecycleError = nil }
        } message: {
            Text(lifecycleError ?? "")
        }
    }

    private func details(for goal: PersonalGoal) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(goal.categoryTitle).foregroundStyle(PipoTheme.muted)
            }

            TicketCard {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Status", value: goal.lifecycleState.title)
                    LabeledContent("Saved", value: money(goal.currentAmount))
                    ProgressView(value: goal.progress)
                        .tint(PipoTheme.green)
                        .accessibilityLabel("Saving progress")
                    LabeledContent("Target", value: money(goal.targetAmount))
                    LabeledContent("Target date", value: dateLabel(goal.targetDate))
                    if let override = goal.plannedContributionOverride {
                        LabeledContent("Planned contribution", value: money(override) + goal.rhythm.unitLabel)
                    }
                    LabeledContent("Saving rhythm", value: PersonalPlanFormatting.rhythmLabel(goal.rhythm, day: goal.preferredSavingDay))
                }
                .font(.subheadline)
            }

            if !goal.subItems.isEmpty {
                PipoBudgetBreakdownCard(
                    lines: goal.subItems.map {
                        PipoBudgetLine(id: $0.id, title: $0.title, amount: $0.amount)
                    },
                    targetAmount: goal.targetAmount
                )
            }

            if goal.canRecordSaving {
                Button("Record a saving", action: recordSaving)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("pipo.goal.recordSaving")
                Button("Pause this goal") {
                    changeLifecycle(of: goal, to: .paused)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.deepPink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("pipo.goal.pause")
                Button("Archive this goal") {
                    changeLifecycle(of: goal, to: .archived)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("pipo.goal.archive")
            } else if goal.lifecycleState == .paused || goal.lifecycleState == .archived {
                Text(goal.lifecycleState == .paused
                     ? "This goal is paused. Nothing was lost."
                     : "This goal is archived. Your saved history is still here.")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.muted)
                Button("Resume this goal") {
                    changeLifecycle(of: goal, to: .active)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("pipo.goal.resume")
            } else {
                Label("Goal completed", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(PipoTheme.green)
            }
        }
    }

    private func changeLifecycle(of goal: PersonalGoal, to state: GoalLifecycleState) {
        guard AccountScope.owns(goal, userID: authStateManager.userID) else { return }
        let old = goal.lifecycleRaw
        guard goal.transition(to: state) else { return }
        do {
            try modelContext.save()
        } catch {
            goal.lifecycleRaw = old
            lifecycleError = "We couldn't save this change. Please try again."
        }
    }
}

func money(_ amount: Int) -> String {
    PersonalPlanFormatting.rupiah(amount)
}

func money(_ amount: Double) -> String {
    if let whole = Int(exactly: amount) { return money(whole) }
    return amount.formatted(.currency(code: "IDR").locale(Locale(identifier: "id_ID")))
}

func dateLabel(_ date: Date) -> String {
    date.formatted(PersonalPlanFormatting.dateStyle)
}

func scheduleTitle(_ schedule: PersonalSavingSchedule, rhythm: SavingRhythm) -> String {
    if schedule.count == 1 { return "1 planned contribution" }
    return "\(schedule.count) \(rhythm.periodLabel)"
}

func scheduleDetails(_ schedule: PersonalSavingSchedule, override: Int? = nil) -> String {
    if let override {
        return "\(schedule.count) planned contributions at \(money(override)) each, from \(dateLabel(schedule.firstDate)) to \(dateLabel(schedule.lastDate))."
    }
    let amount = money(schedule.amount)
    let timeline = schedule.count == 1
        ? "Make one planned contribution on \(dateLabel(schedule.firstDate))."
        : "\(schedule.count) planned contributions from \(dateLabel(schedule.firstDate)) to \(dateLabel(schedule.lastDate))."
    return "\(timeline) Aim to save \(amount) each time. Your last contribution may be smaller."
}
