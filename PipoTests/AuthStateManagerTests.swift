import SwiftData
import XCTest
@testable import Pipo

final class AuthStateManagerTests: XCTestCase {
    func testSignInAndSignOutUpdateAuthenticationState() async {
        let userID = UUID()
        let result = await MainActor.run {
            () -> (states: [AuthState], signedInUserID: UUID?, signedOutUserID: UUID?) in
            let manager = AuthStateManager()
            let initialState = manager.authState
            manager.signIn(userID: userID)
            let signedInState = manager.authState
            let signedInUserID = manager.userID
            manager.signOut()
            return (
                [initialState, signedInState, manager.authState],
                signedInUserID,
                manager.userID
            )
        }

        XCTAssertEqual(
            result.states,
            [.unauthenticated, .authenticated, .unauthenticated]
        )
        XCTAssertEqual(result.signedInUserID, userID)
        XCTAssertNil(result.signedOutUserID)
    }


    func testAccountResetClearsPendingDepositRouteAndMilestone() async {
        await MainActor.run {
            let nav = NavigationManager()
            nav.requestDeposit(goalID: UUID())
            nav.transactionDidComplete(xpEarned: 300, streakDays: 5)
            nav.navigate(to: .createGoal)
            nav.resetAccountContext()
            XCTAssertNil(nav.pendingDepositGoalID)
            XCTAssertFalse(nav.isMilestonePresented)
            XCTAssertEqual(nav.milestoneStreakDays, 0)
            XCTAssertEqual(nav.path.count, 0)
        }
    }

    func testNavigationManagerPushesAndPopsRoutes() async {
        let pathCounts = await MainActor.run { () -> [Int] in
            let manager = NavigationManager()
            manager.navigate(to: .savingRhythm)
            let pushedCount = manager.path.count
            manager.pop()
            let poppedCount = manager.path.count
            manager.navigate(to: .reviewGroupSaving)
            manager.popToRoot()
            return [pushedCount, poppedCount, manager.path.count]
        }

        XCTAssertEqual(pathCounts, [1, 0, 0])
    }
    @MainActor
    func testConfirmedAccountDeletionErasesOnlyThatOwnersRecords() throws {
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let owner = UUID()
        let other = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func goal(_ owner: UUID?) -> PersonalGoal {
            PersonalGoal(
                title: "Saving", category: .trip, targetAmount: 200_000,
                startDate: start, targetDate: start.addingTimeInterval(86400 * 14),
                ownerUserID: owner
            )
        }
        let mine = goal(owner)
        let theirs = goal(other)
        let legacy = goal(nil)
        mine.subItems = [SubItem(title: "Flight", amount: 60_000)]
        let myTransaction = SavingTransaction(goalId: mine.id, amount: 60_000, userID: owner)
        let theirTransaction = SavingTransaction(goalId: theirs.id, amount: 60_000, userID: other)
        let orphanTransaction = SavingTransaction(goalId: legacy.id, amount: 10_000)
        for value in [mine, theirs, legacy] { context.insert(value) }
        for value in [myTransaction, theirTransaction, orphanTransaction] { context.insert(value) }
        for value in [UserProfile(userID: owner), UserProfile(userID: other), UserProfile(userID: nil)] {
            context.insert(value)
        }
        try context.save()

        let personalization = OnboardingPersonalization(
            nickname: "Owner", motivation: .exploring,
            viewedWidgetGuide: true, completedAt: start
        )
        XCTAssertTrue(OnboardingProfileStore.save(personalization, for: owner))
        XCTAssertNotNil(OnboardingProfileStore.load(for: owner))

        // Even a direct call cannot locally purge data before server approval.
        XCTAssertThrowsError(
            try AccountDeletionLocalData.complete(for: owner, in: context)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalGoal>()).count, 3)

        AccountDeletionLocalData.markServerDeleted(owner)
        try AccountDeletionLocalData.complete(for: owner, in: context)

        let remainingGoals = try context.fetch(FetchDescriptor<PersonalGoal>())
        XCTAssertEqual(remainingGoals.count, 2)
        XCTAssertFalse(remainingGoals.contains { $0.ownerUserID == owner })
        XCTAssertTrue(remainingGoals.contains { $0.ownerUserID == other })
        XCTAssertTrue(remainingGoals.contains { $0.ownerUserID == nil })
        let remainingTransactions = try context.fetch(FetchDescriptor<SavingTransaction>())
        XCTAssertEqual(remainingTransactions.count, 2)
        XCTAssertFalse(remainingTransactions.contains { $0.userID == owner })
        XCTAssertTrue(remainingTransactions.contains { $0.userID == other })
        XCTAssertTrue(remainingTransactions.contains { $0.userID == nil })
        let remainingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(remainingProfiles.count, 2)
        XCTAssertTrue(remainingProfiles.contains { $0.userID == other })
        XCTAssertTrue(remainingProfiles.contains { $0.userID == nil })
        XCTAssertNil(OnboardingProfileStore.load(for: owner))
    }

    @MainActor
    func testDeletionRetryRemovesOnlyServerConfirmedAccount() throws {
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let deletedUser = UUID()
        let activeOtherUser = UUID()
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(PersonalGoal(
            title: "Deleted user", category: .trip, targetAmount: 100_000,
            startDate: from, targetDate: from.addingTimeInterval(86400),
            ownerUserID: deletedUser
        ))
        context.insert(PersonalGoal(
            title: "Other user", category: .gift, targetAmount: 200_000,
            startDate: from, targetDate: from.addingTimeInterval(86400),
            ownerUserID: activeOtherUser
        ))
        try context.save()
        AccountDeletionLocalData.markServerDeleted(deletedUser)
        AccountDeletionLocalData.retryPending(in: context)

        let goals = try context.fetch(FetchDescriptor<PersonalGoal>())
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals.first?.ownerUserID, activeOtherUser)
        // Retry is idempotent: it cannot delete another account.
        AccountDeletionLocalData.retryPending(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalGoal>()).count, 1)
    }

}
