import SwiftData
import SwiftUI
import PhotosUI
import UIKit

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

    private func money(_ value: Int) -> String {
        PipoGoalCurrency.formatted(Int64(value), code: plan.currencyCode)
    }
    private func money(_ value: Double) -> String {
        PipoGoalCurrency.display(value, code: plan.currencyCode)
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
                    amount: PipoGoalCurrency.parseMinor(item.amount, code: plan.currencyCode).map {
                        NSDecimalNumber(decimal: PipoGoalCurrency.decimal($0, code: plan.currencyCode)).doubleValue
                    } ?? -1
                )
            },
            targetAmount: plan.targetAmount,
            currencyCode: plan.currencyCode,
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
        goal.currencyCode = plan.currencyCode
        goal.targetMinorUnits = plan.targetMinorUnits
        goal.recordedMinorUnits = 0
        goal.plannedContributionOverride = plan.contributionOverride
        goal.subItems = plan.breakdown.compactMap { item in
            guard let minor = PipoGoalCurrency.parseMinor(item.amount, code: plan.currencyCode) else { return nil }
            let amount = PipoGoalCurrency.decimal(minor, code: plan.currencyCode)
            return SubItem(title: item.cleanTitle,
                amount: NSDecimalNumber(decimal: amount).doubleValue,
                amountMinorUnits: minor)
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
    @Query private var transactions: [SavingTransaction]
    @Query private var profiles: [UserProfile]
    @Environment(AuthStateManager.self) private var authStateManager
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(\.modelContext) private var modelContext
    @State private var lifecycleError: String?
    @State private var showingSavingJournal = false
    @State private var showingMoneyOutPreview = false
    @State private var showingPlanRevisionPreview = false

    init(goalID: UUID, onBack: @escaping () -> Void, recordSaving: @escaping () -> Void) {
        _goals = Query(filter: #Predicate<PersonalGoal> { $0.id == goalID })
        self.onBack = onBack
        self.recordSaving = recordSaving
    }

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    @State private var photoRevision = 0
    @State private var removingPhoto = false
    @State private var isLoadingPhoto = false

    private var ownedGoal: PersonalGoal? {
        guard let goal = goals.first,
              AccountScope.owns(goal, userID: authStateManager.userID)
        else { return nil }
        return goal
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let goal = ownedGoal {
                    VStack(alignment: .leading, spacing: 0) {
                        PipoGoalPhotoHero(
                            photos: goal.goalPhoto.flatMap(UIImage.init(data:)).map { [$0] } ?? [],
                            goalTitle: goal.title,
                            heroHeight: min(280, max(190, geometry.size.height * 0.37)),
                            selectedPhoto: $selectedPhoto,
                            isProcessing: isLoadingPhoto,
                            onBack: onBack
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pipo.goal.photoHero")

                        details(for: goal)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 28)
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Button("Goals", systemImage: "chevron.left", action: onBack)
                            .frame(minHeight: 44)
                        ContentUnavailableView("Goal unavailable", systemImage: "target")
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let goal = ownedGoal, goal.canRecordSaving {
                    Button("Record a saving", action: recordSaving)
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("pipo.goal.recordSaving")
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(.white)
                }
            }
        }
        .background(.white)
        .foregroundStyle(PipoTheme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedPhoto) { _, item in
            photoRevision += 1
            guard let item else { return }
            let revision = photoRevision
            Task { await saveSelectedPhoto(item, revision: revision) }
        }
        .sheet(isPresented: $showingSavingJournal) {
            NavigationStack {
                ScrollView {
                    if let goal = ownedGoal {
                        PipoActivityHistoryDCard(
                            transactions: ownedHistory(for: goal),
                            titleForGoal: { _ in goal.title },
                            currencyForGoal: { _ in goal.effectiveCurrencyCode }
                        )
                        .padding(20)
                    }
                }
                .navigationTitle("Saving journal")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingSavingJournal = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlanRevisionPreview) {
            if let goal = ownedGoal {
                PipoManagePlanV2Sheet(goal: goal) {
                    showingPlanRevisionPreview = false
                }
            }
        }
        .sheet(isPresented: $showingMoneyOutPreview) {
            if let goal = ownedGoal {
                PipoMoneyOutReviewSheet(
                    availableAmount: goal.currentAmount,
                    targetAmount: goal.targetAmount,
                    xpEarned: UserProfile.existing(
                        for: authStateManager.userID, in: profiles
                    )?.totalXP ?? 0,
                    onClose: { showingMoneyOutPreview = false }
                )
            }
        }
        .alert("Goal not updated", isPresented: Binding(
            get: { lifecycleError != nil },
            set: { if !$0 { lifecycleError = nil } }
        )) {
            Button("OK", role: .cancel) { lifecycleError = nil }
        } message: {
            Text(lifecycleError ?? "")
        }
        .alert("Photo not saved", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
        .confirmationDialog(
            "Remove this goal photo?",
            isPresented: $removingPhoto,
            titleVisibility: .visible
        ) {
            Button("Remove photo", role: .destructive) { removePhoto() }
            Button("Keep photo", role: .cancel) {}
        } message: {
            Text("This removes the photo stored on this device. It won't change your savings.")
        }
    }

    @MainActor
    private func saveSelectedPhoto(_ selection: PhotosPickerItem, revision: Int) async {
        guard let original = ownedGoal,
              let owner = authStateManager.userID
        else { return }
        let goalID = original.id
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let bytes = try await selection.loadTransferable(type: Data.self)
            else { throw PipoGoalPhotoProcessingError.unreadable }
            let sanitized = try PipoGoalPhotoProcessing.prepare(bytes)
            guard revision == photoRevision,
                  authStateManager.userID == owner,
                  let goal = ownedGoal,
                  goal.id == goalID
            else { return }
            let prior = goal.goalPhoto
            goal.goalPhoto = sanitized
            do {
                try modelContext.save()
            } catch {
                goal.goalPhoto = prior
                throw error
            }
        } catch {
            guard revision == photoRevision,
                  authStateManager.userID == owner else { return }
            photoError = "This photo couldn't be saved. Choose a JPG, PNG, or HEIC photo under 12 MB."
        }
        if revision == photoRevision { selectedPhoto = nil }
    }

    private func removePhoto() {
        guard let goal = ownedGoal else { return }
        let previous = goal.goalPhoto
        goal.goalPhoto = nil
        do {
            try modelContext.save()
        } catch {
            goal.goalPhoto = previous
            photoError = "Your previous photo is still here. Please try again."
        }
    }

    private func details(for goal: PersonalGoal) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(goal.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    Text("\(Int(goal.progress * 100))% logged")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PipoTheme.deepPink)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Manually recorded")
                            .font(.caption)
                            .foregroundStyle(PipoTheme.muted)
                        Text(money(goal.currentAmount, goal: goal))
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Target")
                            .font(.caption)
                            .foregroundStyle(PipoTheme.muted)
                        Text(money(goal.targetAmount, goal: goal))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .monospacedDigit()
                    }
                }
                ProgressView(value: goal.progress)
                    .tint(PipoTheme.pink)
                    .accessibilityLabel("Manually recorded saving progress")
                    .accessibilityValue("\(Int(goal.progress * 100)) percent")
                    .accessibilityIdentifier("pipo.goal.progress")
                Text("Pipo doesn't hold or move your money.")
                    .font(.caption)
                    .foregroundStyle(PipoTheme.muted)
            }
            .accessibilityIdentifier("pipo.goal.summary")

            PipoGoalProgressBCard(
                quarterWayEarned: UserProfile.existing(
                    for: authStateManager.userID, in: profiles
                )?.unlockedBadgeIds.contains(PipoBadge.quarterWay.rawValue) ?? false,
                onOpenCollection: {
                    navigationManager.requestAchievementsOpen()
                    onBack()
                }
            )

            if goal.goalPhoto != nil {
                Button("Remove goal photo") { removingPhoto = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.muted)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("pipo.goal.removePhoto")
            }

            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("Status", value: goal.lifecycleState.title)
                LabeledContent("Target date", value: dateLabel(goal.targetDate))
                if let override = goal.plannedContributionOverride {
                    LabeledContent("Planned contribution", value: money(override, goal: goal) + goal.rhythm.unitLabel)
                }
                LabeledContent(
                    "Saving rhythm",
                    value: PersonalPlanFormatting.rhythmLabel(
                        goal.rhythm, day: goal.preferredSavingDay
                    )
                )
            }
            .font(.subheadline)
            .padding(.vertical, 4)

            if !goal.subItems.isEmpty {
                PipoBudgetBreakdownCard(
                    lines: goal.subItems.map {
                        PipoBudgetLine(id: $0.id, title: $0.title, amount: $0.amount)
                    },
                    targetAmount: goal.targetAmount,
                    currencyCode: goal.effectiveCurrencyCode
                )
            }

            PipoActivityHistoryDCard(
                transactions: ownedHistory(for: goal),
                titleForGoal: { _ in goal.title },
                currencyForGoal: { _ in goal.effectiveCurrencyCode }
            )
            if goal.lifecycleState == .completed {
                PipoCompletionBCard(goal: goal) {
                    showingSavingJournal = true
                }
            }

            if !goal.isGroupGoal {
                Button("Review plan changes") {
                    showingPlanRevisionPreview = true
                }
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.deepPink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("pipo.goal.planRevisionPreview")
            }

            // Review-only until #42's atomic account-scoped ledger is deployed.
            // Never imply this moves money from a bank or saves a withdrawal.
            if goal.currentAmount > 0 && !goal.isGroupGoal {
                Button("Review money used elsewhere") {
                    showingMoneyOutPreview = true
                }
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.deepPink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("pipo.goal.moneyOutPreview")
            }

            HStack(alignment: .bottom, spacing: 12) {
                Text("Pipo's here, cheering for every little save.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PipoV4HeadCrop()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color(red: 1, green: 241.0 / 255, blue: 244.0 / 255),
                in: RoundedRectangle(cornerRadius: 22)
            )

            if goal.canRecordSaving {
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

    private func ownedHistory(for goal: PersonalGoal) -> [SavingTransaction] {
        guard let owner = authStateManager.userID, goal.ownerUserID == owner else { return [] }
        return transactions
            .filter { $0.userID == owner && $0.goalId == goal.id }
            .sorted { $0.date > $1.date }
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


/// Native hero uses only private goal-owned media. Never substitute the Figma
/// Bali example image for user content. The gallery supports multiple distinct
/// frames, but V1 persistence deliberately supplies zero or one.
private struct PipoGoalPhotoHero: View {
    let photos: [UIImage]
    let goalTitle: String
    let heroHeight: CGFloat
    @Binding var selectedPhoto: PhotosPickerItem?
    let isProcessing: Bool
    let onBack: () -> Void
    @State private var index = 0

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if photos.isEmpty {
                    Rectangle()
                        .fill(Color(red: 1, green: 241.0 / 255, blue: 244.0 / 255))
                        .overlay {
                            VStack(spacing: 9) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30, weight: .medium))
                                    .accessibilityHidden(true)
                                Text("Make this goal yours")
                                    .font(.headline)
                                Text("Add a photo whenever you're ready")
                                    .font(.caption)
                            }
                            .foregroundStyle(PipoTheme.ink)
                        }
                        .accessibilityLabel("No photo added for \(goalTitle)")
                } else {
                    TabView(selection: $index) {
                        ForEach(photos.indices, id: \.self) { photoIndex in
                            GeometryReader { geometry in
                                Image(uiImage: photos[photoIndex])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: geometry.size.width,
                                        height: geometry.size.height
                                    )
                                    .clipped()
                            }
                            .tag(photoIndex)
                            .accessibilityLabel(
                                "Goal photo \(photoIndex + 1) of \(photos.count)"
                            )
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityIdentifier("pipo.goal.photoGallery")
                }
            }
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Label("Goals", systemImage: "chevron.left")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("pipo.goal.heroBack")
                    Spacer(minLength: 0)
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Photos", systemImage: "photo")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("pipo.goal.photoPicker")
                    .disabled(isProcessing)
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .background {
                    // Controls retain contrast on extremely bright imagery.
                    Color.clear
                }
                .padding(.horizontal, 20)
                .padding(.top, 9)

                Spacer(minLength: 0)

                if isProcessing {
                    ProgressView("Saving photo")
                        .tint(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .padding(.bottom, 12)
                } else if photos.count > 1 {
                    Button {
                        index = (index + 1) % photos.count
                    } label: {
                        Text("\(index + 1)/\(photos.count)")
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .frame(minWidth: 70, minHeight: 44)
                    }
                    .foregroundStyle(.white)
                    .background(
                        Color.black.opacity(0.64),
                        in: Capsule()
                    )
                    .accessibilityLabel(
                        "Photo \(index + 1) of \(photos.count). Show next photo"
                    )
                    .accessibilityIdentifier("pipo.goal.photoCounter")
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(height: heroHeight)
        .clipped()
        .onChange(of: photos.count) { _, count in
            if count <= index { index = 0 }
        }
    }
}

/// PhotosPicker provides limited photo selection; the original source bytes
/// and EXIF/location metadata are never persisted. File size and decoded
/// dimensions are validated before drawing a new, clean, reduced-size JPEG.
enum PipoGoalPhotoProcessingError: Error {
    case unreadable
    case tooLarge
}

@MainActor
enum PipoGoalPhotoProcessing {
    static func prepare(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024,
              let image = UIImage(data: data),
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0,
              image.size.width * image.size.height <= 36_000_000
        else { throw PipoGoalPhotoProcessingError.unreadable }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let newSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let output = UIGraphicsImageRenderer(size: newSize, format: format)
            .jpegData(withCompressionQuality: 0.72) { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        guard !output.isEmpty, output.count <= 1_500_000
        else { throw PipoGoalPhotoProcessingError.tooLarge }
        return output
    }
}


func money(_ amount: Double, goal: PersonalGoal) -> String {
    let code = goal.effectiveCurrencyCode
    let exact = amount == goal.targetAmount ? goal.exactTargetMinor :
        amount == goal.currentAmount ? goal.exactRecordedMinor : nil
    return PipoGoalCurrency.display(amount, code: code, exactMinor: exact)
}

func money(_ amount: Int, goal: PersonalGoal) -> String {
    PipoGoalCurrency.formatted(Int64(amount), code: goal.effectiveCurrencyCode)
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

/// Issue #42 preview: uses exactly the approved three D-family cards.
/// This does not write transactions, alter XP or claim to withdraw bank funds.
/// The final confirmation stays gated until the Supabase atomic ledger exists.
private struct PipoMoneyOutReviewSheet: View {
    let availableAmount: Double
    let targetAmount: Double
    let xpEarned: Int
    let onClose: () -> Void

    @State private var amountText = ""
    @State private var note = ""
    @State private var reviewed = false
    @State private var route: PipoSavingRoute = .keepDate

    private var validAmount: Double? {
        PipoMoneyOutPreview.amount(from: amountText, available: availableAmount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pipo only records money you tell it about. Nothing moves from your bank.")
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.muted)
                    PipoInputEditingDCard(
                        amount: $amountText, note: $note,
                        available: availableAmount,
                        onReview: { reviewed = true }
                    )
                    if reviewed, let validAmount {
                        PipoFinancialImpactDCard(
                            before: availableAmount,
                            amountUsed: validAmount,
                            xpEarnedSoFar: xpEarned
                        )
                        // No future estimates without an actual revised schedule.
                        PipoSavingDecisionsDCard(
                            selection: $route,
                            suggestedAmount: nil,
                            laterDate: nil
                        )
                        Text("A validated future schedule and server-side ledger are required before confirming either option.")
                            .font(.footnote)
                            .foregroundStyle(PipoTheme.muted)
                        Button("Saving changes isn't available yet") {}
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(true)
                            .accessibilityHint("Requires a secure, account-verified money-out ledger.")
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Money used elsewhere")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}
