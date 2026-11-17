import Foundation
import SwiftData
import SwiftUI

enum GroupReviewSection: Sendable {
    case goal
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
}

private enum GroupSavingSheet: String, Identifiable {
    case inviteMember
    case paywall

    var id: String { rawValue }
}

@MainActor
struct ReviewGroupSavingView: View {
    let review: GroupSavingReviewData

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(AuthStateManager.self) private var authStateManager
    @Query private var goals: [PersonalGoal]
    @Query private var profiles: [UserProfile]

    @State private var activeSheet: GroupSavingSheet?
    @State private var groupPlan: GroupSavingPlan
    @State private var errorMessage: String?

    private let groupSavingManager = GroupSavingManager()
    private let onBack: () -> Void
    private let onEdit: (GroupReviewSection) -> Void
    private let onCreate: () -> Void

    init(
        review: GroupSavingReviewData,
        onBack: @escaping () -> Void,
        onEdit: @escaping (GroupReviewSection) -> Void,
        onCreate: @escaping () -> Void
    ) {
        self.review = review
        _groupPlan = State(
            initialValue: GroupSavingPlan(
                title: review.title,
                breakdown: review.breakdown.map {
                    GroupGoalTarget(id: $0.id, title: $0.title, amount: $0.amount)
                },
                members: review.members
            )
        )
        self.onBack = onBack
        self.onEdit = onEdit
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pageHeader
                    reviewTicket
                    Text("Pipo tracks self-reported contributions. It does not hold or transfer funds, and creating a group does not set up automatic payments. Money stays with each member.")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(PipoTheme.cream)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .preferredColorScheme(.light)
        .onAppear(perform: syncEntitlements)
        .onChange(of: currentProfile?.purchasedGroupSlots) { _, _ in
            syncEntitlements()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .inviteMember:
                InviteGroupMemberSheet(onInvite: inviteMember)
            case .paywall:
                PaywallView(isGroup: true)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert(
            "Unable to create group goal",
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PipoTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Group saving plan")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                Spacer()
                Text("7 of 7")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.muted)
            }

            HStack(spacing: 8) {
                ForEach(0..<7) { index in
                    Capsule()
                        .fill(index < 6 ? PipoTheme.green : PipoTheme.pink)
                        .frame(height: 5)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Review & create")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.muted)
                Text("Your group saving plan")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PipoTheme.ink)
                Text("Review your draft. You can edit any part before you create it.")
                    .font(.body)
                    .foregroundStyle(PipoTheme.muted)
            }
        }
    }

    private var reviewTicket: some View {
        TicketCard {
            VStack(alignment: .leading, spacing: 0) {
                goalSection
                ticketDivider
                squadSection
                ticketDivider
                timelineSection
                ticketDivider
                contributionSection
                ticketDivider
                membersSection
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(review.category.uppercased(), systemImage: "airplane")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(PipoTheme.muted)
                Spacer()
                Text("DRAFT SAVINGS PLAN")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(PipoTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(review.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PipoTheme.ink)
                Spacer()
                editButton(for: .goal)
            }

            Text("\(review.category) · \(review.goalDescription)")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)

            VStack(alignment: .leading, spacing: 6) {
                Text("Shared target")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.muted)
                currency(groupSavingManager.totalSquadTarget(for: groupPlan))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(PipoTheme.pink)
            }

        }
    }

    private var squadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(review.groupName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PipoTheme.ink)
                Spacer()
                editButton(for: .squad)
            }

            Label("\(review.visibility) · You — Group Admin", systemImage: "lock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.muted)

            Text(review.groupDescription)
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)

            VStack(alignment: .leading, spacing: 10) {
                Text("Target breakdown")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                ForEach(review.breakdown) { item in
                    HStack {
                        Text(item.title)
                            .foregroundStyle(PipoTheme.muted)
                        Spacer()
                        currency(item.amount)
                            .foregroundStyle(PipoTheme.ink)
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .padding(.top, 4)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Timeline", section: .timeline)
            HStack(alignment: .top, spacing: 18) {
                dateColumn("Plan starts", date: review.plannedStartDate)
                dateColumn("Target date", date: review.targetDate)
            }
            Text("\(review.contributionCount) monthly contributions, including the start and end dates. A date to aim for, not a guaranteed finish.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
        }
    }

    private var contributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Contribution rules", section: .contributionRules)
            keyValueRow("Mode", value: review.contributionMode)
            keyValueRow("Rhythm", value: review.rhythm)
            if let plannedContributionAmount = review.plannedContributionAmount {
                keyValueRow(
                    "Planned contribution",
                    value: currencyText(plannedContributionAmount)
                )
            }
            keyValueRow("Expected contributors", value: "\(contributorCount) (including you)")

            VStack(alignment: .leading, spacing: 6) {
                Text("Estimate per member")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.muted)
                currency(estimatePerMember)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PipoTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 14))

            Text(estimateExplanation)
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Members & invitations", section: .members)
            keyValueRow("Joined members", value: joinedMemberSummary)
            keyValueRow(
                "Invitations",
                value: invitationSummary
            )

            VStack(spacing: 10) {
                ForEach(groupPlan.members) { member in
                    HStack(spacing: 10) {
                        Text(initials(for: member.name))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(member.status == .accepted ? .white : PipoTheme.muted)
                            .frame(width: 34, height: 34)
                            .background(
                                member.status == .accepted ? PipoTheme.green : PipoTheme.cream,
                                in: Circle()
                            )
                            .opacity(avatarOpacity(for: member.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PipoTheme.ink)
                            Text(member.role)
                                .font(.caption)
                                .foregroundStyle(PipoTheme.muted)
                            if let share = groupSavingManager.memberContributionSplits(for: groupPlan)[member.id] {
                                Text("Target share \(currencyText(share))")
                                    .font(.caption2)
                                    .foregroundStyle(PipoTheme.muted)
                            }
                        }
                        Spacer(minLength: 4)
                        Menu {
                            ForEach(InvitationStatus.allCases, id: \.self) { status in
                                Button(status.title) {
                                    updateInvitation(for: member, to: status)
                                }
                            }
                        } label: {
                            Text(member.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(member.status == .accepted ? PipoTheme.green : PipoTheme.muted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            Button("Invite Member", systemImage: "person.badge.plus") {
                activeSheet = .inviteMember
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PipoTheme.pink)
            .buttonStyle(.plain)

            if acceptedMemberCount <= 1 {
                Text("The invite link becomes available after group creation. No one else has joined yet.")
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.muted)
            }
        }
    }

    private var ticketDivider: some View {
        TicketSeparator()
            .padding(.vertical, 20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Back", action: onBack)
                .buttonStyle(SecondaryActionButtonStyle())
            Button("Create Group Saving", action: confirmCreation)
                .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.white)
        .overlay(alignment: .top) {
            PipoTheme.border.frame(height: 1)
        }
    }

    private var activeGroupGoalCount: Int {
        goals.filter { $0.isGroupGoal }.count
    }

    private var currentProfile: UserProfile? {
        UserProfile.existing(for: authStateManager.userID, in: profiles)
    }

    private var acceptedMemberCount: Int {
        groupPlan.members.filter { $0.status == .accepted }.count
    }

    private var invitationCount: Int {
        groupPlan.members.filter { $0.status == .invited }.count
    }

    private var contributorCount: Int {
        groupPlan.members.filter { $0.status != .declined }.count
    }

    private var estimatePerMember: Double {
        guard review.contributionCount > 0, contributorCount > 0 else { return 0 }
        return groupSavingManager.totalSquadTarget(for: groupPlan)
            / Double(review.contributionCount)
            / Double(contributorCount)
    }

    private func confirmCreation() {
        guard subscriptionManager.canCreateGoal(
            isGroup: true,
            activeCount: activeGroupGoalCount
        ) else {
            activeSheet = .paywall
            return
        }

        let existingProfile = currentProfile
        let profile = existingProfile ?? UserProfile(userID: authStateManager.userID)
        let previousCount = profile.activeGroupGoalsCount
        let previousUserID = profile.userID
        let goal = PersonalGoal(
            title: review.title,
            category: .trip,
            targetAmount: groupSavingManager.totalSquadTarget(for: groupPlan),
            startDate: review.plannedStartDate,
            targetDate: review.targetDate,
            rhythm: .monthly,
            isGroupGoal: true
        )
        profile.userID = authStateManager.userID
        profile.activeGroupGoalsCount = activeGroupGoalCount + 1
        modelContext.insert(goal)
        if existingProfile == nil {
            modelContext.insert(profile)
        }

        do {
            try modelContext.save()
            onCreate()
        } catch {
            modelContext.delete(goal)
            profile.userID = previousUserID
            profile.activeGroupGoalsCount = previousCount
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

    private func inviteMember(nameOrHandle: String) -> String? {
        do {
            _ = try groupSavingManager.inviteMember(nameOrHandle: nameOrHandle, to: &groupPlan)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func updateInvitation(for member: GroupMember, to status: InvitationStatus) {
        do {
            try groupSavingManager.updateInvitation(
                memberID: member.id,
                to: status,
                in: &groupPlan
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func avatarOpacity(for status: InvitationStatus) -> Double {
        status == .accepted ? 1 : 0.4
    }

    private var estimateExplanation: String {
        let totalPeriods = max(review.contributionCount, 0)
        let contributors = contributorCount
        guard totalPeriods > 0, contributors > 0 else {
            return "Add at least one contributor and contribution period to see an estimate."
        }
        let contributionTotal = currencyText(groupSavingManager.totalSquadTarget(for: groupPlan))
        let perMember = currencyText(estimatePerMember)
        return "\(contributionTotal) ÷ \(totalPeriods) ÷ \(contributors) = \(perMember). Assumes Rp0 initial savings and equal contribution across all \(totalPeriods) periods. The estimate may change if participation or the timeline changes."
    }

    private var joinedMemberSummary: String {
        acceptedMemberCount == 1
            ? "\(acceptedMemberCount) (you)"
            : "\(acceptedMemberCount)"
    }

    private var invitationSummary: String {
        invitationCount == 0
            ? "0 sent · not yet shared"
            : "\(invitationCount) sent"
    }

    private func sectionTitle(_ title: String, section: GroupReviewSection) -> some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(PipoTheme.ink)
            Spacer()
            editButton(for: section)
        }
    }

    private func editButton(for section: GroupReviewSection) -> some View {
        Button("Edit") {
            onEdit(section)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PipoTheme.pink)
        .buttonStyle(.plain)
    }

    private func dateColumn(_ title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PipoTheme.muted)
            Text(
                date.formatted(
                    .dateTime.day().month(.wide).year().locale(Locale(identifier: "en_GB"))
                )
            )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PipoTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(PipoTheme.muted)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(PipoTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func currency(_ amount: Double) -> some View {
        Text(amount, format: .currency(code: "IDR").locale(Locale(identifier: "id_ID")).precision(.fractionLength(0)))
    }

    private func currencyText(_ amount: Double) -> String {
        amount.formatted(.currency(code: "IDR").locale(Locale(identifier: "id_ID")).precision(.fractionLength(0)))
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

@MainActor
private struct InviteGroupMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onInvite: (String) -> String?

    @State private var nameOrHandle = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    TextField("Name or @handle", text: $nameOrHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite", action: invite)
                        .disabled(nameOrHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                "Could not invite member",
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
    }

    private func invite() {
        if let error = onInvite(nameOrHandle) {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}

#Preview {
    ReviewGroupSavingView(
        review: MockData.groupSavingReview,
        onBack: {},
        onEdit: { _ in },
        onCreate: {}
    )
    .environment(AuthStateManager())
    .environment(SubscriptionManager())
    .environment(StoreKitManager())
    .modelContainer(
        for: [PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self],
        inMemory: true
    )
}
