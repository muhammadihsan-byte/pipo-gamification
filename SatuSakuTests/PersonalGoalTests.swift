import XCTest
@testable import SatuSaku

final class PersonalGoalTests: XCTestCase {
    func testProgressAndRemainingAmountAreBoundedByTarget() {
        let goal = PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 100,
            currentAmount: 125,
            targetDate: .now
        )

        XCTAssertEqual(goal.progress, 1)
        XCTAssertEqual(goal.remainingAmount, 0)
    }

    func testOnlyMatchingAuthenticatedOwnerCanAccessGoals() {
        let firstUser = UUID()
        let secondUser = UUID()
        let firstGoal = PersonalGoal(
            title: "Trip",
            category: .trip,
            targetAmount: 1_000,
            targetDate: .now,
            userID: firstUser
        )
        let secondGoal = PersonalGoal(
            title: "Gift",
            category: .gift,
            targetAmount: 2_000,
            targetDate: .now,
            userID: secondUser
        )

        XCTAssertTrue(firstGoal.isOwned(by: firstUser))
        XCTAssertFalse(firstGoal.isOwned(by: secondUser))
        XCTAssertFalse(firstGoal.isOwned(by: nil))
        XCTAssertTrue(secondGoal.isOwned(by: secondUser))
        XCTAssertFalse(secondGoal.isOwned(by: firstUser))
    }

    func testLegacyGoalIsPreservedButNotAutomaticallyClaimed() {
        let legacyGoal = PersonalGoal(
            title: "Old goal",
            category: .house,
            targetAmount: 500,
            targetDate: .now
        )

        XCTAssertNil(legacyGoal.userID)
        XCTAssertFalse(legacyGoal.isOwned(by: UUID()))
        XCTAssertFalse(legacyGoal.isOwned(by: nil))
        XCTAssertEqual(legacyGoal.title, "Old goal")
    }

    func testAnonymousProfileCannotBeUsedForAnotherAccount() {
        let firstUser = UUID()
        let secondUser = UUID()
        let anonymousProfile = UserProfile()
        let firstProfile = UserProfile(userID: firstUser)
        let profiles = [anonymousProfile, firstProfile]

        XCTAssertTrue(UserProfile.existing(for: firstUser, in: profiles) === firstProfile)
        XCTAssertNil(UserProfile.existing(for: secondUser, in: profiles))
        XCTAssertNil(UserProfile.existing(for: nil, in: profiles))
    }

    func testProgressIsZeroWhenTargetIsNotPositive() {
        let goal = PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 0,
            currentAmount: 50,
            targetDate: .now
        )

        XCTAssertEqual(goal.progress, 0)
        XCTAssertEqual(goal.remainingAmount, 0)
    }
}
