import Foundation
import SwiftData
import SwiftUI

enum GroupReviewSection: Sendable {
    case goal
    case target
    case squad
    case timeline
    case contributionRules
    case members
}

struct GroupGoalBreakdownItem: Identifiable, Sendable {
    let id: String
    let title: String
    let amount: Double
}

typealias GroupReviewMember = GroupMember

struct GroupSavingReviewData: Sendable {
    let title: String
    let category: String
    let targetAmount: Double
    let groupName: String
    let visibility: String
    let goalDescription: String
    let groupDescription: String
    let breakdown: [GroupGoalBreakdownItem]
    let plannedStartDate: Date
    let targetDate: Date
    let contributionCount: Int
    let contributionMode: String
    var rhythm: String
    let members: [GroupReviewMember]
    var plannedContributionAmount: Double? = nil
    var modelCategory: GoalCategory = .trip
    var modelRhythm: SavingRhythm = .monthly
    var preferredDay: Int?
    var details: GroupPlanDetails?
    var goalPhoto: Data?
    var groupPhoto: Data?
    var skippedInvites = false
}

extension GroupPlanDraft {
    func review(creatorID: UUID?) -> GroupSavingReviewData? {
        guard valid(.review), let category, let target, let end, let contributors else { return nil }
        let details = GroupPlanDetails(groupName: groupName.trimmed, groupDescription: groupDescription.trimmed,
                                      goalDescription: goalDescription.trimmed, expectedContributors: contributors,
                                      mode: mode, checkIn: mode == .flexible ? checkIn : nil,
                                      preparedMembers: preparedMembers, creatorID: creatorID)
        let breakdown = usesBreakdown ? items.compactMap { row -> GroupGoalBreakdownItem? in
            guard let amount = row.rupiah else { return nil }
            return GroupGoalBreakdownItem(id: row.id.uuidString, title: row.cleanTitle, amount: Double(amount))
        } : []
        return GroupSavingReviewData(
            title: title.trimmed, category: categoryTitle, targetAmount: Double(target),
            groupName: details.groupName, visibility: "Private · Invite-only",
            goalDescription: details.goalDescription, groupDescription: details.groupDescription,
            breakdown: breakdown, plannedStartDate: start, targetDate: end,
            contributionCount: schedule?.count ?? 0, contributionMode: mode.rawValue,
            rhythm: mode == .equal ? PersonalPlanFormatting.rhythmLabel(rhythm, day: preferredDay)
                : checkIn.map { "\($0.title) check-in" } ?? "No scheduled check-in",
            members: [GroupMember(id: creatorID?.uuidString ?? "creator", name: "You", role: "Group Admin", status: .accepted)],
            plannedContributionAmount: estimate.map { Double($0) }, modelCategory: category.modelCategory,
            modelRhythm: mode == .equal ? rhythm : .flexible, preferredDay: mode == .equal ? preferredDay : nil,
            details: details, goalPhoto: goalPhoto, groupPhoto: groupPhoto, skippedInvites: inviteLater
        )
    }
}

extension GroupSavingReviewData {
    @MainActor
    func insertGoal(in context: ModelContext) throws {
        let goal = PersonalGoal(title: title, category: modelCategory, customCategory: category,
                                targetAmount: targetAmount, startDate: plannedStartDate,
                                targetDate: targetDate, rhythm: modelRhythm,
                                preferredSavingDay: preferredDay, isGroupGoal: true)
        if let details { goal.groupDetails = try JSONEncoder().encode(details) }
        goal.goalPhoto = goalPhoto
        goal.groupPhoto = groupPhoto
        goal.subItems = breakdown.map { SubItem(title: $0.title, amount: $0.amount) }
        context.insert(goal)
    }
}

@MainActor
struct ReviewGroupSavingView: View {
    let review: GroupSavingReviewData
    let onBack: () -> Void
    let onEdit: (GroupReviewSection) -> Void
    let onCreate: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(AuthStateManager.self) private var auth
    @Query private var profiles: [UserProfile]
    @State private var ticket = false
    @State private var busy = false
    @State private var showPaywall = false
    @State private var error: String?

    var body: some View {
        SavingPlanPage(flowTitle: "Group saving plan", stepNumber: 7, count: 7,
                       stepTitle: GroupPlanStep.review.title, onBack: onBack) {
            GroupStepIntro("Your group saving plan", "Review your draft. You can edit any part before you create it.")
            Picker("Review layout", selection: $ticket) {
                Text("Summary").tag(false)
                Text("Ticket").tag(true)
            }.pickerStyle(.segmented)
            if ticket {
                TicketCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DRAFT SAVINGS PLAN").font(.caption.bold()).foregroundStyle(PersonalPlanStyle.berry)
                        goal
                        TicketSeparator()
                        group
                        TicketSeparator()
                        target
                        TicketSeparator()
                        timeline
                        TicketSeparator()
                        rules
                        TicketSeparator()
                        members
                    }
                }
            } else {
                group.groupPlanCard()
                goal.groupPlanCard()
                target.groupPlanCard()
                timeline.groupPlanCard()
                rules.groupPlanCard()
                members.groupPlanCard()
            }
            Text("Pipo tracks self-reported contributions. Money stays with each member.")
                .font(.footnote).foregroundStyle(PersonalPlanStyle.muted)
        } footer: {
            PersonalPlanActions(back: onBack, title: busy ? "Creating…" : "Create Group Saving",
                                dimmed: busy, action: { busy = true })
        }
        .disabled(busy)
        .task(id: busy) {
            if busy { confirmCreation() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(isGroup: true).presentationDetents([.medium, .large])
        }
        .alert("Couldn’t save your group", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func section(_ title: String, _ section: GroupReviewSection,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { onEdit(section) } label: { Text("Edit").frame(minWidth: 44, minHeight: 44) }
                    .font(.caption.bold()).accessibilityLabel("Edit \(title)")
            }
            content()
        }.font(.subheadline)
    }

    private var group: some View {
        section(review.groupName, .squad) {
            PlanPhotoPreview(data: review.groupPhoto)
            Text("\(review.visibility) · You — Group Admin")
            if !review.groupDescription.isEmpty { Text(review.groupDescription) }
        }
    }
    private var goal: some View {
        section(review.title, .goal) {
            PlanPhotoPreview(data: review.goalPhoto)
            Text(review.category)
            if !review.goalDescription.isEmpty { Text(review.goalDescription) }
        }
    }
    private var target: some View {
        section(review.breakdown.isEmpty ? "Shared target" : "Target breakdown", .target) {
            ForEach(review.breakdown) { row in LabeledContent(row.title, value: money(row.amount)) }
            LabeledContent("Shared target", value: money(review.targetAmount)).bold()
        }
    }
    private var timeline: some View {
        section("Timeline", .timeline) {
            LabeledContent("Plan starts", value: dateLabel(review.plannedStartDate))
            LabeledContent("Target date", value: dateLabel(review.targetDate))
            if review.contributionCount > 0 { Text("\(review.contributionCount) planned contributions") }
        }
    }
    private var rules: some View {
        section("Contribution rules", .contributionRules) {
            LabeledContent("Mode", value: review.contributionMode)
            LabeledContent("Rhythm", value: review.rhythm)
            LabeledContent("Expected contributors", value: "\(review.details?.expectedContributors ?? review.members.count) (including you)")
            if let estimate = review.plannedContributionAmount {
                LabeledContent("Estimate per member", value: money(estimate) + review.modelRhythm.unitLabel)
            } else { Text("Members choose when and how much to save.") }
        }
    }
    private var members: some View {
        section("Members & invitations", .members) {
            LabeledContent("Joined members", value: "\(review.members.filter { $0.status == .accepted }.count) (you)")
            Text("0 invitations sent")
            ForEach(review.details?.preparedMembers ?? [], id: \.self) { name in LabeledContent(name, value: "Unsent") }
            if review.skippedInvites { Text("Invitations skipped for now.") }
        }
    }

    private func confirmCreation() {
        let profile = UserProfile.existing(for: auth.userID, in: profiles)
        subscription.updateEntitlements(purchasedPersonalSlots: profile?.purchasedPersonalSlots ?? 0,
                                        purchasedGroupSlots: profile?.purchasedGroupSlots ?? 0)
        // Isolate this transaction from pending edits elsewhere in the app.
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        do {
            let count = try writer.fetchCount(FetchDescriptor<PersonalGoal>(predicate: #Predicate { $0.isGroupGoal }))
            guard subscription.canCreateGoal(isGroup: true, activeCount: count) else {
                busy = false
                showPaywall = true
                return
            }
            let savedProfiles = try writer.fetch(FetchDescriptor<UserProfile>())
            let owner = UserProfile.existing(for: auth.userID, in: savedProfiles) ?? UserProfile(userID: auth.userID)
            if owner.modelContext == nil { writer.insert(owner) }
            owner.userID = auth.userID
            owner.activeGroupGoalsCount = count + 1
            try review.insertGoal(in: writer)
            try writer.save()
            onCreate()
        } catch {
            writer.rollback()
            busy = false
            self.error = error.localizedDescription
        }
    }
}
