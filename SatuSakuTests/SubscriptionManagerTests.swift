import SwiftData
import XCTest
@testable import SatuSaku

final class SubscriptionManagerTests: XCTestCase {
    @MainActor
    func testFreeTierAllowsOnePersonalAndOneGroupGoal() {
        let manager = SubscriptionManager()

        XCTAssertTrue(manager.canCreateGoal(isGroup: false, activeCount: 0))
        XCTAssertFalse(manager.canCreateGoal(isGroup: false, activeCount: 1))
        XCTAssertTrue(manager.canCreateGoal(isGroup: true, activeCount: 0))
        XCTAssertFalse(manager.canCreateGoal(isGroup: true, activeCount: 1))
    }

    @MainActor
    func testPlanInputRemainsAvailableBeforeFinalSlotCheck() {
        let manager = SubscriptionManager()
        let start = Date(timeIntervalSince1970: 0)
        let target = Calendar(identifier: .gregorian)
            .date(byAdding: .month, value: 18, to: start)!
        let plan = PersonalGoalPlan(
            title: "Long-term goal",
            category: .house,
            targetAmount: 10_000,
            breakdown: [GoalBreakdownDraft(title: "Materials", amount: "5000")],
            startDate: start,
            targetDate: target,
            rhythm: .monthly
        )

        XCTAssertEqual(plan.title, "Long-term goal")
        XCTAssertEqual(plan.breakdown.count, 1)
        XCTAssertEqual(plan.targetDate, target)
        XCTAssertFalse(manager.canCreateGoal(isGroup: false, activeCount: 1))
    }

    @MainActor
    func testPurchasedSlotsIncreaseAllowancePermanently() {
        let manager = SubscriptionManager()

        manager.updateEntitlements(purchasedPersonalSlots: 1, purchasedGroupSlots: 1)

        XCTAssertEqual(manager.purchasedPersonalSlots, 1)
        XCTAssertEqual(manager.purchasedGroupSlots, 1)
        XCTAssertTrue(manager.canCreateGoal(isGroup: false, activeCount: 1))
        XCTAssertTrue(manager.canCreateGoal(isGroup: true, activeCount: 1))
    }

    @MainActor
    func testSwitchingAccountsClearsAllowancesAndRejectsStaleUpdates() {
        let manager = SubscriptionManager()
        let firstUser = UUID()
        let secondUser = UUID()

        manager.switchAccount(to: firstUser)
        manager.updateEntitlements(
            purchasedPersonalSlots: 2,
            purchasedGroupSlots: 1,
            for: firstUser
        )
        XCTAssertEqual(manager.purchasedPersonalSlots, 2)

        manager.switchAccount(to: secondUser)
        XCTAssertEqual(manager.purchasedPersonalSlots, 0)
        XCTAssertEqual(manager.purchasedGroupSlots, 0)

        manager.updateEntitlements(
            purchasedPersonalSlots: 99,
            purchasedGroupSlots: 99,
            for: firstUser
        )
        XCTAssertEqual(manager.purchasedPersonalSlots, 0)
        XCTAssertEqual(manager.purchasedGroupSlots, 0)

        manager.updateEntitlements(
            purchasedPersonalSlots: 0,
            purchasedGroupSlots: 3,
            for: secondUser
        )
        XCTAssertEqual(manager.purchasedPersonalSlots, 0)
        XCTAssertEqual(manager.purchasedGroupSlots, 3)

        manager.switchAccount(to: nil)
        XCTAssertEqual(manager.purchasedGroupSlots, 0)
    }

    @MainActor
    func testPurchasedSlotBalancesPersistOnUserProfile() async throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = UserProfile(purchasedPersonalSlots: 2, purchasedGroupSlots: 3)
        context.insert(profile)
        try context.save()

        let persistedProfile = try XCTUnwrap(
            context.fetch(FetchDescriptor<UserProfile>()).first
        )
        XCTAssertEqual(persistedProfile.purchasedPersonalSlots, 2)
        XCTAssertEqual(persistedProfile.purchasedGroupSlots, 3)
    }
}
