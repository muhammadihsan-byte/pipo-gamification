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
}
