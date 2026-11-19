import XCTest
@testable import Pipo

final class GroupSavingManagerTests: XCTestCase {
    func testInviteAndInvitationStatusChanges() throws {
        let manager = GroupSavingManager()
        var plan = makePlan(members: [])

        let member = try manager.inviteMember(nameOrHandle: "  @pipo  ", to: &plan)
        XCTAssertEqual(member.status, .invited)
        XCTAssertEqual(member.handle, "@pipo")
        XCTAssertEqual(plan.members.count, 1)

        try manager.updateInvitation(memberID: member.id, to: .accepted, in: &plan)
        XCTAssertEqual(plan.members.first?.status, .accepted)
        try manager.updateInvitation(memberID: member.id, to: .declined, in: &plan)
        XCTAssertEqual(plan.members.first?.status, .declined)
    }

    func testInviteRejectsEmptyOrDuplicateMembers() throws {
        let manager = GroupSavingManager()
        var plan = makePlan(members: [
            GroupMember(id: "member-1", name: "Alex", status: .invited)
        ])

        XCTAssertThrowsError(try manager.inviteMember(nameOrHandle: "  ", to: &plan))
        XCTAssertThrowsError(try manager.inviteMember(nameOrHandle: "alex", to: &plan))
        XCTAssertEqual(plan.members.count, 1)
    }

    func testSquadTargetSplitsAcrossAcceptedAndInvitedMembers() {
        let manager = GroupSavingManager()
        var plan = makePlan(members: [
            GroupMember(id: "accepted", name: "Alex", status: .accepted),
            GroupMember(id: "invited", name: "Sam", status: .invited),
            GroupMember(id: "declined", name: "Lee", status: .declined)
        ])

        XCTAssertEqual(manager.totalSquadTarget(for: plan), 900)
        let splits = manager.memberContributionSplits(for: plan)
        XCTAssertEqual(splits["accepted"], 450)
        XCTAssertEqual(splits["invited"], 450)
        XCTAssertNil(splits["declined"])

        plan.members.removeAll()
        XCTAssertTrue(manager.memberContributionSplits(for: plan).isEmpty)
    }

    func testSubContributionsRequireAnAcceptedMemberAndTrackSquadTotal() throws {
        let manager = GroupSavingManager()
        var plan = makePlan(members: [
            GroupMember(id: "accepted", name: "Alex", status: .accepted),
            GroupMember(id: "invited", name: "Sam", status: .invited)
        ])

        XCTAssertThrowsError(
            try manager.recordContribution(amount: 50, from: "invited", in: &plan)
        )
        _ = try manager.recordContribution(amount: 125, from: "accepted", in: &plan)
        _ = try manager.recordContribution(amount: 75, from: "accepted", in: &plan)
        XCTAssertEqual(manager.totalContributed(in: plan), 200)
    }

    private func makePlan(members: [GroupMember]) -> GroupSavingPlan {
        GroupSavingPlan(
            title: "Squad trip",
            breakdown: [
                GroupGoalTarget(id: "flight", title: "Flights", amount: 600),
                GroupGoalTarget(id: "hotel", title: "Hotel", amount: 300)
            ],
            members: members
        )
    }
}
