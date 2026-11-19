import Foundation

enum InvitationStatus: String, CaseIterable, Hashable, Sendable {
    case invited
    case accepted
    case declined
}

extension InvitationStatus {
    var title: String {
        switch self {
        case .invited: "Invited"
        case .accepted: "Accepted"
        case .declined: "Declined"
        }
    }
}

struct GroupMember: Identifiable, Sendable {
    let id: String
    var name: String
    var handle: String?
    var role: String
    var status: InvitationStatus

    init(
        id: String = UUID().uuidString,
        name: String,
        handle: String? = nil,
        role: String = "Squad member",
        status: InvitationStatus
    ) {
        self.id = id
        self.name = name
        self.handle = handle
        self.role = role
        self.status = status
    }
}

struct GroupGoalTarget: Identifiable, Sendable {
    let id: String
    let title: String
    let amount: Double
}

struct GroupSubContribution: Identifiable, Sendable {
    let id: UUID
    let memberID: String
    let amount: Double
    let date: Date

    init(id: UUID = UUID(), memberID: String, amount: Double, date: Date = .now) {
        self.id = id
        self.memberID = memberID
        self.amount = amount
        self.date = date
    }
}

struct GroupSavingPlan: Sendable {
    let title: String
    var breakdown: [GroupGoalTarget]
    var members: [GroupMember]
    var contributions: [GroupSubContribution] = []
}

enum GroupSavingError: LocalizedError {
    case emptyMemberName
    case duplicateMember
    case memberNotFound
    case memberNotAccepted
    case invalidContribution
    case totalOutOfRange

    var errorDescription: String? {
        switch self {
        case .emptyMemberName:
            return "Enter a member name or handle."
        case .duplicateMember:
            return "That member has already been added."
        case .memberNotFound:
            return "That member is no longer in this group."
        case .memberNotAccepted:
            return "Only accepted members can record contributions."
        case .invalidContribution:
            return "Enter a contribution greater than zero."
        case .totalOutOfRange:
            return "The group target or contribution total is too large."
        }
    }
}

struct GroupSavingManager {
    func inviteMember(nameOrHandle: String, to plan: inout GroupSavingPlan) throws -> GroupMember {
        let value = nameOrHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GroupSavingError.emptyMemberName }
        let canonicalValue = canonicalMemberIdentifier(value)
        guard !plan.members.contains(where: {
            canonicalMemberIdentifier($0.name).caseInsensitiveCompare(canonicalValue) == .orderedSame
                || $0.handle.map(canonicalMemberIdentifier)?.caseInsensitiveCompare(canonicalValue) == .orderedSame
        }) else {
            throw GroupSavingError.duplicateMember
        }

        let member = GroupMember(
            name: value,
            handle: value.hasPrefix("@") ? value : nil,
            status: .invited
        )
        plan.members.append(member)
        return member
    }

    private func canonicalMemberIdentifier(_ value: String) -> String {
        value.hasPrefix("@") ? String(value.dropFirst()) : value
    }

    func updateInvitation(
        memberID: String,
        to status: InvitationStatus,
        in plan: inout GroupSavingPlan
    ) throws {
        guard let index = plan.members.firstIndex(where: { $0.id == memberID }) else {
            throw GroupSavingError.memberNotFound
        }
        plan.members[index].status = status
    }

    func totalSquadTarget(for plan: GroupSavingPlan) -> Double {
        plan.breakdown.reduce(0) { $0 + $1.amount }
    }

    func memberContributionSplits(for plan: GroupSavingPlan) -> [String: Double] {
        let contributors = plan.members.filter { $0.status != .declined }
        guard !contributors.isEmpty else { return [:] }
        let share = totalSquadTarget(for: plan) / Double(contributors.count)
        return Dictionary(uniqueKeysWithValues: contributors.map { ($0.id, share) })
    }

    func totalContributed(in plan: GroupSavingPlan) -> Double {
        plan.contributions.reduce(0) { $0 + $1.amount }
    }

    func recordContribution(
        amount: Double,
        from memberID: String,
        in plan: inout GroupSavingPlan,
        date: Date = .now
    ) throws -> GroupSubContribution {
        guard amount.isFinite, amount > 0 else {
            throw GroupSavingError.invalidContribution
        }
        guard let member = plan.members.first(where: { $0.id == memberID }) else {
            throw GroupSavingError.memberNotFound
        }
        guard member.status == .accepted else {
            throw GroupSavingError.memberNotAccepted
        }
        guard (totalContributed(in: plan) + amount).isFinite else {
            throw GroupSavingError.totalOutOfRange
        }

        let contribution = GroupSubContribution(memberID: memberID, amount: amount, date: date)
        plan.contributions.append(contribution)
        return contribution
    }
}
