import Observation
import SwiftUI

enum Route: Hashable, Sendable {
    case auth
    case dashboard
    case createGoal
    case createGroupPlan
    case personalGoal(UUID)
    case savingRhythm
    case reviewGroupSaving
    case milestoneCelebration
    case paywall(isGroup: Bool)
}

@MainActor
@Observable
final class NavigationManager {
    var path = NavigationPath()
    var isMilestonePresented = false
    var milestoneStreakDays = 0
    var milestoneNewBadges: [String] = []
    var milestoneIsFirstSave = false
    var pendingAchievementsRequest = false
    var milestoneXPEarned = GamificationManager.xpPerSaving
    var selectedRhythm: SavingRhythm = .monthly
    var preferredDepositDay = 25
    var plannedContributionAmount: Double?
    var pendingDepositGoalID: UUID?

    init(initialRoute: Route? = nil) {
        if let initialRoute {
            path.append(initialRoute)
        }
    }

    func navigate(to route: Route) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }

    func resetAccountContext() {
        popToRoot()
        pendingDepositGoalID = nil
        isMilestonePresented = false
        milestoneXPEarned = GamificationManager.xpPerSaving
        milestoneStreakDays = 0
        milestoneNewBadges = []
        milestoneIsFirstSave = false
        pendingAchievementsRequest = false
        selectedRhythm = .monthly
        preferredDepositDay = 25
        plannedContributionAmount = nil
    }

    func requestDeposit(goalID: UUID) {
        popToRoot()
        pendingDepositGoalID = goalID
    }

    func consumeDepositRequest() -> UUID? {
        defer { pendingDepositGoalID = nil }
        return pendingDepositGoalID
    }

    func transactionDidComplete(
        xpEarned: Int, streakDays: Int, badgeTitles: [String] = [],
        isFirstSave: Bool = false
    ) {
        milestoneXPEarned = xpEarned
        milestoneStreakDays = max(streakDays, 0)
        milestoneNewBadges = badgeTitles
        milestoneIsFirstSave = isFirstSave
        isMilestonePresented = true
    }

    func requestAchievementsOpen() {
        pendingAchievementsRequest = true
    }

    func consumeAchievementsRequest() -> Bool {
        defer { pendingAchievementsRequest = false }
        return pendingAchievementsRequest
    }
}
