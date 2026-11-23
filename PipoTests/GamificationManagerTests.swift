import XCTest
import UIKit
@testable import Pipo

final class GamificationManagerTests: XCTestCase {
    @MainActor
    func testRecordingSavingAwardsXPUpdatesProfileAndGoal() async throws {
        let manager = GamificationManager()
        let profile = UserProfile(totalXP: 1_200)
        let goal = makeGoal()

        let transaction = try manager.recordSaving(
            amount: 250,
            goal: goal,
            profile: profile,
            date: makeDate(day: 1)
        )

        XCTAssertEqual(transaction.amount, 250)
        XCTAssertEqual(transaction.xpEarned, 300)
        XCTAssertEqual(profile.totalXP, 1_500)
        XCTAssertEqual(profile.currentLevel, 2)
        XCTAssertEqual(profile.streakDays, 1)
        XCTAssertEqual(goal.currentAmount, 250)
    }

    func testLevelThresholdsRequireEveryFifteenHundredXP() {
        let manager = GamificationManager()

        XCTAssertEqual(manager.level(for: 0), 1)
        XCTAssertEqual(manager.level(for: 1_499), 1)
        XCTAssertEqual(manager.level(for: 1_500), 2)
        XCTAssertEqual(manager.level(for: 3_000), 3)
    }

    func testStreakContinuesWithinRhythmWindowAndResetsWhenOverdue() {
        let manager = GamificationManager()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lastSavingDate = makeDate(day: 1)

        let onTimeStreak = manager.streakDays(
            afterSavingOn: makeDate(day: 8),
            lastSavingDate: lastSavingDate,
            currentStreak: 4,
            rhythm: .weekly,
            calendar: calendar
        )
        let overdueStreak = manager.streakDays(
            afterSavingOn: makeDate(day: 9),
            lastSavingDate: lastSavingDate,
            currentStreak: 4,
            rhythm: .weekly,
            calendar: calendar
        )

        XCTAssertEqual(onTimeStreak, 5)
        XCTAssertEqual(overdueStreak, 1)
    }

    func testDailyRhythmAllowsDepositAnyTimeOnTheNextCalendarDay() {
        let manager = GamificationManager()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lastSavingDate = makeDate(day: 1)
        let lateOnNextDay = makeDate(day: 2).addingTimeInterval(11 * 60 * 60)

        let streak = manager.streakDays(
            afterSavingOn: lateOnNextDay,
            lastSavingDate: lastSavingDate,
            currentStreak: 2,
            rhythm: .daily,
            calendar: calendar
        )

        XCTAssertEqual(streak, 3)
    }

    func testAdditionalSavingOnSameDayDoesNotIncreaseStreak() {
        let manager = GamificationManager()
        let date = makeDate(day: 1)

        let streak = manager.streakDays(
            afterSavingOn: date.addingTimeInterval(60 * 60),
            lastSavingDate: date,
            currentStreak: 3,
            rhythm: .daily
        )

        XCTAssertEqual(streak, 3)
    }

    @MainActor
    func testInvalidDepositDoesNotChangeProfileOrGoal() async {
        let manager = GamificationManager()
        let profile = UserProfile()
        let goal = makeGoal()

        XCTAssertThrowsError(
            try manager.recordSaving(
                amount: 0,
                goal: goal,
                profile: profile,
                date: makeDate(day: 1)
            )
        )
        XCTAssertEqual(profile.totalXP, 0)
        XCTAssertEqual(profile.streakDays, 0)
        XCTAssertEqual(goal.currentAmount, 0)
    }


    func testDashboardCadenceUsesFocusedGoalPeriodsNotGlobalStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = makeDate(day: 1)
        let logs = [makeDate(day: 3), makeDate(day: 9), makeDate(day: 16)]
        XCTAssertEqual(
            DashboardActivity.consecutivePeriods(
                dates: logs, rhythm: .weekly,
                startDate: start, asOf: makeDate(day: 17), calendar: calendar
            ), 3
        )
        XCTAssertEqual(
            DashboardActivity.consecutivePeriods(
                dates: logs, rhythm: .weekly,
                startDate: start, asOf: makeDate(day: 30), calendar: calendar
            ), 0
        )
    }

    func testDashboardFlexibleGoalsNeverClaimAStreak() {
        XCTAssertEqual(
            DashboardActivity.consecutivePeriods(
                dates: [makeDate(day: 2), makeDate(day: 4)],
                rhythm: .flexible,
                startDate: makeDate(day: 1),
                asOf: makeDate(day: 5)
            ), 0
        )
    }

    func testDashboardPeriodCountsMultipleSavesInOnePeriodOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            DashboardActivity.consecutivePeriods(
                dates: [makeDate(day: 2), makeDate(day: 2).addingTimeInterval(100), makeDate(day: 3)],
                rhythm: .daily,
                startDate: makeDate(day: 1),
                asOf: makeDate(day: 4),
                calendar: calendar
            ), 2
        )
    }


    @MainActor
    func testDashboardWeeklyNextDateRespectsPreferredWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1),
            targetDate: makeDate(day: 31),
            rhythm: .weekly,
            preferredSavingDay: 1
        )
        let next = DashboardSchedule.nextDate(for: goal, asOf: makeDate(day: 5), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: next!), 11)
    }

    @MainActor
    func testDashboardMonthlyNextDateClampsPreferredThirtyFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let target = calendar.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12))!
        let goal = PersonalGoal(
            title: "New laptop", category: .gadget, targetAmount: 10_000,
            startDate: makeDate(day: 20),
            targetDate: target,
            rhythm: .monthly,
            preferredSavingDay: 31
        )
        let next = DashboardSchedule.nextDate(for: goal, asOf: february, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: next!), 2)
        XCTAssertEqual(calendar.component(.day, from: next!), 28)
    }


    @MainActor
    func testMixedGoalHistoryCannotInflateConsistentPeriods() throws {
        let owner = UUID()
        let goal = PersonalGoal(title: "Trip", category: .trip, targetAmount: 900,
                                startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
                                rhythm: .weekly, ownerUserID: owner)
        let anotherGoal = UUID()
        let profile = UserProfile(userID: owner, streakDays: 17)
        let unrelated = SavingTransaction(goalId: anotherGoal, amount: 100, date: makeDate(day: 2), userID: owner)
        let saving = try GamificationManager().recordSaving(
            amount: 100, goal: goal, profile: profile, date: makeDate(day: 9),
            priorTransactions: [unrelated]
        )
        XCTAssertEqual(saving.amount, 100)
        XCTAssertEqual(profile.streakDays, 1)
    }

    @MainActor
    func testFlexibleSavingNeverCreatesPunitiveStreak() throws {
        let goal = PersonalGoal(title: "Flexible", category: .other, targetAmount: 900,
                                startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
                                rhythm: .flexible)
        let profile = UserProfile(streakDays: 50)
        _ = try GamificationManager().recordSaving(
            amount: 100, goal: goal, profile: profile, date: makeDate(day: 9)
        )
        XCTAssertEqual(profile.streakDays, 0)
        XCTAssertEqual(SavingConsistency.consecutivePeriods(
            dates: [makeDate(day: 9)], rhythm: .flexible,
            startDate: makeDate(day: 1), asOf: makeDate(day: 10)
        ), 0)
    }

    func testGracePeriodAndMissedPeriodReset() {
        let start = makeDate(day: 1)
        let history = [makeDate(day: 2), makeDate(day: 9)]
        XCTAssertEqual(SavingConsistency.consecutivePeriods(
            dates: history, rhythm: .weekly,
            startDate: start, asOf: makeDate(day: 20)
        ), 2)
        XCTAssertEqual(SavingConsistency.consecutivePeriods(
            dates: history, rhythm: .weekly,
            startDate: start, asOf: makeDate(day: 27)
        ), 0)
        XCTAssertTrue(SavingConsistency.isRecovery(
            priorDates: history, newDate: makeDate(day: 27),
            rhythm: .weekly, startDate: start
        ))
    }

    func testDaylightSavingAndMonthEndUseCalendarPeriods() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let jan31 = date(2026, 1, 31)
        let monthly = [jan31, date(2026, 2, 28), date(2026, 3, 31)]
        XCTAssertEqual(SavingConsistency.consecutivePeriods(
            dates: monthly, rhythm: .monthly,
            startDate: jan31, asOf: date(2026, 3, 31), calendar: cal
        ), 3)
        let marchStart = date(2026, 3, 1)
        let weekly = [marchStart, date(2026, 3, 8), date(2026, 3, 15)]
        XCTAssertEqual(SavingConsistency.consecutivePeriods(
            dates: weekly, rhythm: .weekly,
            startDate: marchStart, asOf: date(2026, 3, 15), calendar: cal
        ), 3)
    }

    @MainActor
    func testBadgeUnlockIsIdempotentAndRejectsOtherAccounts() throws {
        let owner = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 400,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, preferredSavingDay: 5, ownerUserID: owner
        )
        let first = SavingTransaction(goalId: goal.id, amount: 100,
                                      date: makeDate(day: 1), userID: owner)
        goal.currentAmount = 100
        let earned = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: first,
            history: [], previousAmount: 0
        )
        XCTAssertTrue(earned.contains(.firstSave))
        XCTAssertTrue(earned.contains(.quarterWay))
        XCTAssertTrue(earned.contains(.planMatch))
        XCTAssertTrue(AchievementEngine.grant(
            profile: profile, goal: goal, transaction: first,
            history: [], previousAmount: 0
        ).isEmpty)
        XCTAssertEqual(Set(profile.unlockedBadgeIds).count, profile.unlockedBadgeIds.count)

        let other = UserProfile(userID: UUID())
        XCTAssertTrue(AchievementEngine.grant(
            profile: other, goal: goal, transaction: first,
            history: [], previousAmount: 0
        ).isEmpty)
        XCTAssertTrue(other.unlockedBadgeIds.isEmpty)
    }

    @MainActor
    func testThreePlannedAndFourPeriodBadgesRequireDistinctScheduledPeriods() {
        let owner = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(title: "Trip", category: .trip, targetAmount: 400,
                                startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
                                rhythm: .weekly, preferredSavingDay: 5, ownerUserID: owner)
        let one = SavingTransaction(goalId: goal.id, amount: 100, date: makeDate(day: 1), userID: owner)
        let two = SavingTransaction(goalId: goal.id, amount: 100, date: makeDate(day: 8), userID: owner)
        let repeatSaving = SavingTransaction(goalId: goal.id, amount: 100,
                                             date: makeDate(day: 8).addingTimeInterval(3600), userID: owner)
        let three = SavingTransaction(goalId: goal.id, amount: 100, date: makeDate(day: 15), userID: owner)
        goal.currentAmount = 400
        let firstTwo = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: repeatSaving,
            history: [one, two], previousAmount: 300
        )
        XCTAssertFalse(firstTwo.contains(.plannedThree))
        let third = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: three,
            history: [one, two], previousAmount: 300
        )
        XCTAssertTrue(third.contains(.plannedThree))
        XCTAssertFalse(third.contains(.periodsFour))
        let four = SavingTransaction(goalId: goal.id, amount: 100, date: makeDate(day: 22), userID: owner)
        let fourth = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: four,
            history: [one, two, three], previousAmount: 300
        )
        XCTAssertTrue(fourth.contains(.periodsFour))
    }

    @MainActor
    func testRecoveryAndExtraSavingHaveRealHistoryTriggers() {
        let owner = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(title: "Trip", category: .trip, targetAmount: 1_000,
                                startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
                                rhythm: .weekly, preferredSavingDay: 5, ownerUserID: owner)
        let first = SavingTransaction(goalId: goal.id, amount: 100, date: makeDate(day: 1), userID: owner)
        let recovered = SavingTransaction(goalId: goal.id, amount: 80, date: makeDate(day: 27), userID: owner)
        goal.currentAmount = 180
        let earned = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: recovered,
            history: [first], previousAmount: 100
        )
        XCTAssertTrue(earned.contains(.recovery))
        XCTAssertFalse(earned.contains(.extraSave))
        XCTAssertFalse(earned.contains(.planMatch))
    }


    @MainActor
    func testFirstStepRequiresTheFirstContributionAcrossAllAccountGoals() {
        let owner = UUID()
        let profile = UserProfile(userID: owner)
        let previousGoal = UUID()
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            ownerUserID: owner
        )
        let existing = SavingTransaction(
            goalId: previousGoal, amount: 80,
            date: makeDate(day: 2), userID: owner
        )
        let next = SavingTransaction(
            goalId: goal.id, amount: 100,
            date: makeDate(day: 3), userID: owner
        )
        goal.currentAmount = 100
        let earned = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: next,
            history: [existing], previousAmount: 0
        )
        XCTAssertFalse(earned.contains(.firstSave))
    }

    @MainActor
    func testExtraSavingRequiresAnotherContributionInTheSamePeriod() {
        let owner = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let first = SavingTransaction(
            goalId: goal.id, amount: 75, date: makeDate(day: 9), userID: owner
        )
        let extra = SavingTransaction(
            goalId: goal.id, amount: 50,
            date: makeDate(day: 10), userID: owner
        )
        goal.currentAmount = 125
        let earned = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: extra,
            history: [first], previousAmount: 75
        )
        XCTAssertTrue(earned.contains(.extraSave))
    }


    @MainActor
    func testOtherGoalLaterSavingCannotRejectValidGoalHistory() throws {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 900,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let accountLatest = makeDate(day: 25)
        let profile = UserProfile(
            userID: owner, totalXP: 300, streakDays: 8,
            lastSavingDate: accountLatest
        )
        let otherGoalSaving = SavingTransaction(
            goalId: UUID(), amount: 200, date: accountLatest, userID: owner
        )
        let saved = try GamificationManager().recordSaving(
            amount: 100, goal: goal, profile: profile,
            date: makeDate(day: 9),
            priorTransactions: [otherGoalSaving]
        )
        XCTAssertEqual(saved.amount, 100)
        XCTAssertEqual(profile.totalXP, 600)
        XCTAssertEqual(profile.streakDays, 1, "Other goal must not inflate this goal's periods")
        XCTAssertEqual(profile.lastSavingDate, accountLatest,
                       "Account-level timestamp cannot move backwards")
        XCTAssertEqual(goal.currentAmount, 100)
    }

    @MainActor
    func testSameGoalOutOfOrderHistoryStillFailsWithoutMutatingAnything() {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Laptop", category: .gadget, targetAmount: 900,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let profile = UserProfile(
            userID: owner, totalXP: 300, streakDays: 2,
            lastSavingDate: makeDate(day: 25)
        )
        let alreadySaved = SavingTransaction(
            goalId: goal.id, amount: 100, date: makeDate(day: 16), userID: owner
        )
        XCTAssertThrowsError(
            try GamificationManager().recordSaving(
                amount: 50, goal: goal, profile: profile,
                date: makeDate(day: 9), priorTransactions: [alreadySaved]
            )
        ) { error in
            guard case GamificationError.depositBeforeLastSaving = error else {
                return XCTFail("Expected goal-scoped chronological rejection")
            }
        }
        XCTAssertEqual(profile.totalXP, 300)
        XCTAssertEqual(profile.streakDays, 2)
        XCTAssertEqual(profile.lastSavingDate, makeDate(day: 25))
        XCTAssertEqual(goal.currentAmount, 0)
    }

    @MainActor
    func testForeignAccountHistoryCannotInflateSameGoalConsistency() throws {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 900,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let profile = UserProfile(userID: owner)
        let ownEarlier = SavingTransaction(
            goalId: goal.id, amount: 50, date: makeDate(day: 2), userID: owner
        )
        let foreign = SavingTransaction(
            goalId: goal.id, amount: 75,
            date: makeDate(day: 9), userID: UUID()
        )
        _ = try GamificationManager().recordSaving(
            amount: 100, goal: goal, profile: profile,
            date: makeDate(day: 16),
            priorTransactions: [ownEarlier, foreign]
        )
        XCTAssertEqual(profile.streakDays, 1,
                       "Foreign account must not fill a missed owner period")
        XCTAssertEqual(profile.lastSavingDate, makeDate(day: 16))
    }

    @MainActor
    func testFlexibleGoalKeepsNoStreakAndPreservesOtherGoalLatestDate() throws {
        let owner = UUID()
        let accountLatest = makeDate(day: 25)
        let goal = PersonalGoal(
            title: "Flexible", category: .other, targetAmount: 900,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .flexible, ownerUserID: owner
        )
        let profile = UserProfile(userID: owner, lastSavingDate: accountLatest)
        _ = try GamificationManager().recordSaving(
            amount: 100, goal: goal, profile: profile,
            date: makeDate(day: 9),
            priorTransactions: [
                SavingTransaction(goalId: UUID(), amount: 200,
                                  date: accountLatest, userID: owner)
            ]
        )
        XCTAssertEqual(profile.streakDays, 0)
        XCTAssertEqual(profile.lastSavingDate, accountLatest)
    }


    @MainActor
    func testEarlierDatedNewGoalNeverReAwardsFirstStepAfterAnotherGoalWasSaved() {
        let owner = UUID()
        // Mimics a migrated profile with saving history but no stored badge IDs.
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let laterOtherGoal = SavingTransaction(
            goalId: UUID(), amount: 80, date: makeDate(day: 25), userID: owner
        )
        let backdatedNewSaving = SavingTransaction(
            goalId: goal.id, amount: 300, date: makeDate(day: 9), userID: owner
        )
        goal.currentAmount = 300
        let unlocked = AchievementEngine.grant(
            profile: profile, goal: goal, transaction: backdatedNewSaving,
            history: [laterOtherGoal], previousAmount: 0
        )
        XCTAssertFalse(unlocked.contains(.firstSave),
                       "Existing account saving blocks a second First Step even if date is later")
        XCTAssertTrue(unlocked.contains(.quarterWay),
                      "Valid progress awards remain available without fabricated First Step")
        XCTAssertFalse(profile.unlockedBadgeIds.contains(PipoBadge.firstSave.rawValue))
    }

    @MainActor
    func testAccountSwitchKeepsOtherAccountsOutOfFirstStepEligibility() {
        let ownerA = UUID()
        let ownerB = UUID()
        let profileA = UserProfile(userID: ownerA)
        let profileB = UserProfile(userID: ownerB)
        let goalB = PersonalGoal(
            title: "New phone", category: .gadget, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .flexible, ownerUserID: ownerB
        )
        let aHistory = SavingTransaction(
            goalId: UUID(), amount: 150, date: makeDate(day: 25), userID: ownerA
        )
        let bFirst = SavingTransaction(
            goalId: goalB.id, amount: 100, date: makeDate(day: 9), userID: ownerB
        )
        goalB.currentAmount = 100
        let awards = AchievementEngine.grant(
            profile: profileB, goal: goalB, transaction: bFirst,
            history: [aHistory], previousAmount: 0
        )
        XCTAssertTrue(awards.contains(.firstSave))
        XCTAssertEqual(profileB.unlockedBadgeIds, [PipoBadge.firstSave.rawValue])
        XCTAssertTrue(profileA.unlockedBadgeIds.isEmpty,
                      "Changing accounts cannot mutate the previous account's rewards")
        XCTAssertTrue(AchievementEngine.grant(
            profile: profileA, goal: goalB, transaction: bFirst,
            history: [aHistory], previousAmount: 0
        ).isEmpty, "Foreign owner cannot grant badges to a different profile")
    }

    @MainActor
    func testReplayedContributionUUIDCannotUnlockBadgesOnMigratedEmptyProfile() {
        let owner = UUID()
        let originalEventID = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            ownerUserID: owner
        )
        goal.currentAmount = 300
        let saved = SavingTransaction(
            id: originalEventID, goalId: goal.id, amount: 300,
            date: makeDate(day: 9), userID: owner
        )
        let replay = SavingTransaction(
            id: originalEventID, goalId: goal.id, amount: 300,
            date: makeDate(day: 9), userID: owner
        )
        XCTAssertTrue(AchievementEngine.grant(
            profile: profile, goal: goal, transaction: replay,
            history: [saved], previousAmount: 0
        ).isEmpty)
        XCTAssertTrue(profile.unlockedBadgeIds.isEmpty,
                      "Replaying an already recorded event must not mint awards")
    }

    @MainActor
    func testDuplicateHistoricalUUIDsCannotInflatePlannedAndMilestoneRewards() {
        let owner = UUID()
        let duplicateID = UUID()
        let profile = UserProfile(userID: owner)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: owner
        )
        let original = SavingTransaction(
            id: duplicateID, goalId: goal.id, amount: 100,
            date: makeDate(day: 1), userID: owner
        )
        let importedDuplicate = SavingTransaction(
            id: duplicateID, goalId: goal.id, amount: 100,
            date: makeDate(day: 8), userID: owner
        )
        let current = SavingTransaction(
            goalId: goal.id, amount: 300,
            date: makeDate(day: 15), userID: owner
        )
        goal.currentAmount = 500
        XCTAssertTrue(AchievementEngine.grant(
            profile: profile, goal: goal, transaction: current,
            history: [original, importedDuplicate], previousAmount: 200
        ).isEmpty)
        XCTAssertTrue(profile.unlockedBadgeIds.isEmpty,
                      "Ambiguous imported event IDs must be reconciled, not rewarded")
    }


    @MainActor
    func testIssue68SparkRegistryHasAllTwentyExactApprovedAssets() {
        // Each size uses its own optically tuned Figma variant.
        XCTAssertEqual(PipoSparkSize.allCases.map(\.rawValue), [16, 20, 24, 40])
        XCTAssertEqual(PipoSparkState.allCases.count, 5)
        var names = Set<String>()
        for state in PipoSparkState.allCases {
            for size in PipoSparkSize.allCases {
                let name = PipoSparkAssets.imageName(state: state, size: size)
                XCTAssertTrue(names.insert(name).inserted, name)
                XCTAssertNotNil(UIImage(named: name), "Missing actual bundled Spark asset: \(name)")
            }
        }
        XCTAssertEqual(names.count, 20)
    }

    func testIssue68FlexibleCadenceCannotShowPendingEndedOrRecovery() {
        for state in PipoSparkState.allCases {
            let model = PipoSparkPresentation.make(
                rhythm: .flexible, proposedState: state,
                recordedSavings: 7, consecutivePeriods: 5
            )
            XCTAssertEqual(model.state, .notStarted)
            XCTAssertEqual(model.label, "Saving at your pace")
            XCTAssertFalse(model.accessibilityLabel.lowercased().contains("missed"))
        }
    }

    func testIssue68UnrecordedOrZeroPeriodStatusNeverClaimsStreak() {
        for state in PipoSparkState.allCases {
            let empty = PipoSparkPresentation.make(
                rhythm: .weekly, proposedState: state,
                recordedSavings: 0, consecutivePeriods: 12
            )
            XCTAssertEqual(empty.state, .notStarted)
            let zero = PipoSparkPresentation.make(
                rhythm: .daily, proposedState: state,
                recordedSavings: 2, consecutivePeriods: 0
            )
            XCTAssertEqual(zero.state, .notStarted)
        }
    }

    func testIssue68ApprovedStatusUsesAccessibleTextNotOnlyColor() {
        let weekly = PipoSparkPresentation.make(
            rhythm: .weekly, proposedState: .active,
            recordedSavings: 4, consecutivePeriods: 4
        )
        XCTAssertEqual(weekly.label, "4-week streak")
        XCTAssertTrue(weekly.accessibilityLabel.contains("On track"))
        let pending = PipoSparkPresentation.make(
            rhythm: .weekly, proposedState: .pending,
            recordedSavings: 4, consecutivePeriods: 4
        )
        XCTAssertTrue(pending.label.contains("still open"))
        XCTAssertTrue(pending.accessibilityLabel.contains("no missed period"))
        let ended = PipoSparkPresentation.make(
            rhythm: .weekly, proposedState: .ended,
            recordedSavings: 3, consecutivePeriods: 2
        )
        XCTAssertEqual(ended.state, .ended)
        XCTAssertTrue(ended.accessibilityLabel.contains("best streak remains saved"))
        let recovery = PipoSparkPresentation.make(
            rhythm: .monthly, proposedState: .recovery,
            recordedSavings: 5, consecutivePeriods: 1
        )
        XCTAssertEqual(recovery.state, .recovery)
        XCTAssertEqual(recovery.label, "Back on track · 1-month streak")
    }


    @MainActor
    func testIssue69WeeklyFourPeriodsStayPerGoalAndIgnoreExtraSameWeek() {
        let userID = UUID()
        let start = makeDate(day: 1)
        let goalA = PersonalGoal(
            title: "Bali", category: .trip, targetAmount: 100_000,
            startDate: start, targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: userID
        )
        let goalB = PersonalGoal(
            title: "Laptop", category: .gadget, targetAmount: 1_000_000,
            startDate: start, targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: userID
        )
        let otherAccount = SavingTransaction(
            goalId: goalB.id, amount: 20, date: makeDate(day: 8), userID: UUID()
        )
        let fourWeeks = [1, 8, 15, 22].map {
            SavingTransaction(goalId: goalA.id, amount: 50,
                              date: makeDate(day: $0), userID: userID)
        }
        let sameWeekExtra = SavingTransaction(
            goalId: goalA.id, amount: 40, date: makeDate(day: 22).addingTimeInterval(45),
            userID: userID
        )
        let bOnly = SavingTransaction(
            goalId: goalB.id, amount: 50, date: makeDate(day: 1), userID: userID
        )
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let all = fourWeeks + [sameWeekExtra, bOnly, otherAccount]
        let a = PipoSparkGoalStatus.presentation(for: goalA, transactions: all,
                           userID: userID, asOf: makeDate(day: 22).addingTimeInterval(600),
                           calendar: cal)
        let b = PipoSparkGoalStatus.presentation(for: goalB, transactions: all,
                           userID: userID, asOf: makeDate(day: 22).addingTimeInterval(600),
                           calendar: cal)
        XCTAssertEqual(a?.state, .active)
        XCTAssertEqual(a?.label, "4-week streak")
        XCTAssertEqual(b?.state, .ended)
        XCTAssertNotEqual(a?.label, b?.label)
        XCTAssertNil(PipoSparkGoalStatus.presentation(
            for: goalA, transactions: all, userID: UUID(),
            asOf: makeDate(day: 22), calendar: cal
        ))
    }

    @MainActor
    func testIssue69PendingIsOpenNotMissedAndExpiredPeriodEndsNeutrally() {
        let userID = UUID()
        let goal = PersonalGoal(
            title: "Emergency fund", category: .house, targetAmount: 1000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: userID
        )
        let history = [1, 8, 15].map {
            SavingTransaction(goalId: goal.id, amount: 10,
                              date: makeDate(day: $0), userID: userID)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let pending = PipoSparkGoalStatus.presentation(
            for: goal, transactions: history, userID: userID,
            asOf: makeDate(day: 22), calendar: cal
        )
        XCTAssertEqual(pending?.state, .pending)
        XCTAssertTrue(pending?.label.contains("3-week streak") == true)
        XCTAssertTrue(pending?.accessibilityLabel.contains("no missed period") == true)
        let ended = PipoSparkGoalStatus.presentation(
            for: goal, transactions: history, userID: userID,
            asOf: makeDate(day: 29), calendar: cal
        )
        XCTAssertEqual(ended?.state, .ended)
        XCTAssertTrue(ended?.accessibilityLabel.contains("Previous 3-week streak") == true)
    }

    @MainActor
    func testIssue69RecoveryStartsAtOneOnlyOnAnActualNewSavingEvent() {
        let userID = UUID()
        let goal = PersonalGoal(
            title: "Holiday", category: .trip, targetAmount: 2000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .weekly, ownerUserID: userID
        )
        let first = SavingTransaction(
            goalId: goal.id, amount: 100, date: makeDate(day: 1), userID: userID
        )
        let recovery = SavingTransaction(
            goalId: goal.id, amount: 100, date: makeDate(day: 22), userID: userID
        )
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(PipoSparkGoalStatus.presentation(
            for: goal, transactions: [first], userID: userID,
            asOf: makeDate(day: 22), calendar: cal
        )?.state, .ended)
        let after = PipoSparkGoalStatus.presentation(
            for: goal, transactions: [first, recovery], userID: userID,
            asOf: makeDate(day: 22).addingTimeInterval(100), calendar: cal
        )
        XCTAssertEqual(after?.state, .recovery)
        XCTAssertEqual(after?.label, "Back on track · 1-week streak")
    }

    @MainActor
    func testIssue69FlexibleFuturePausedAndDuplicateJournalFailClosed() {
        let userID = UUID()
        let goal = PersonalGoal(
            title: "Open ended", category: .house, targetAmount: 1_000,
            startDate: makeDate(day: 1), targetDate: makeDate(day: 31),
            rhythm: .flexible, ownerUserID: userID
        )
        let logged = SavingTransaction(
            goalId: goal.id, amount: 100, date: makeDate(day: 8), userID: userID
        )
        let flexible = PipoSparkGoalStatus.presentation(
            for: goal, transactions: [logged], userID: userID,
            asOf: makeDate(day: 15)
        )
        XCTAssertEqual(flexible?.state, .notStarted)
        XCTAssertEqual(flexible?.label, "Saving at your pace")
        XCTAssertTrue(goal.transition(to: .paused))
        XCTAssertNil(PipoSparkGoalStatus.presentation(
            for: goal, transactions: [logged], userID: userID,
            asOf: makeDate(day: 15)
        ))
        XCTAssertTrue(goal.transition(to: .active))
        goal.rhythm = .weekly
        let duplicate = SavingTransaction(
            id: logged.id, goalId: goal.id, amount: 100,
            date: makeDate(day: 15), userID: userID
        )
        let unsafe = PipoSparkGoalStatus.presentation(
            for: goal, transactions: [logged, duplicate], userID: userID,
            asOf: makeDate(day: 15)
        )
        XCTAssertEqual(unsafe?.state, .notStarted)
        let futureOnly = PipoSparkGoalStatus.presentation(
            for: goal, transactions: [SavingTransaction(
                goalId: goal.id, amount: 10, date: makeDate(day: 31), userID: userID
            )], userID: userID, asOf: makeDate(day: 15)
        )
        XCTAssertEqual(futureOnly?.state, .notStarted)
    }

    @MainActor
    private func makeGoal() -> PersonalGoal {
        PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 10_000,
            startDate: makeDate(day: 1),
            targetDate: makeDate(day: 31),
            rhythm: .weekly
        )
    }

    private func makeDate(day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = 12
        return components.date!
    }
}


// #93 / Wave A: pure, read-only Journey projection regressions. These tests
// deliberately do not unlock badges, write SwiftData, or invent event dates.
@MainActor
final class PipoJourneyWaveAProjectionTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int = 2026, _ month: Int, _ day: Int,
                      hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = utc
        components.timeZone = utc.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }

    private func goal(owner: UUID?, code: String = "IDR") -> PersonalGoal {
        PersonalGoal(
            title: "Actual saving plan", category: .other,
            targetAmount: 1_000, currencyCode: code,
            startDate: date(2026, 10, 1),
            targetDate: date(2030, 1, 1),
            ownerUserID: owner
        )
    }

    private func entry(
        goal: PersonalGoal, owner: UUID?, on date: Date,
        code: String? = nil, minor: Int64? = nil, amount: Double = 100,
        id: UUID = UUID()
    ) -> SavingTransaction {
        SavingTransaction(
            id: id, goalId: goal.id, amount: amount,
            amountMinorUnits: minor, currencyCode: code,
            xpEarned: 300, date: date, userID: owner
        )
    }

    func testOwnerIsolationQuarantinesOwnerlessAndForeignGoalEntries() {
        let alice = UUID()
        let bob = UUID()
        let a = goal(owner: alice)
        let b = goal(owner: bob)
        let ownerless = goal(owner: nil)
        let real = entry(goal: a, owner: alice, on: date(2026, 11, 7))
        let forged = entry(goal: b, owner: alice, on: date(2026, 11, 6))
        let foreign = entry(goal: b, owner: bob, on: date(2026, 11, 5))
        let unowned = entry(goal: ownerless, owner: alice, on: date(2026, 11, 4))
        let missingOwner = entry(goal: a, owner: nil, on: date(2026, 11, 3))
        let records = PipoJourneyProjection.entries(
            goals: [a, b, ownerless],
            transactions: [real, real, forged, foreign, unowned, missingOwner],
            ownerID: alice, calendar: utc
        )
        XCTAssertEqual(records.map(\.id), [real.id],
                       "Repeated UUID, cross-account and ownerless history must never appear")
        XCTAssertEqual(PipoJourneyProjection.entries(
            goals: [a, b], transactions: [real], ownerID: nil,
            calendar: utc
        ).count, 0)
    }

    func testMonthlyFilterUsesLocalCalendarMonthNotThirtyDays() {
        let owner = UUID()
        let g = goal(owner: owner)
        let oct = entry(goal: g, owner: owner, on: date(2026, 10, 31, hour: 23))
        let nov = entry(goal: g, owner: owner, on: date(2026, 11, 1, hour: 0))
        let now = date(2026, 11, 23)
        let rows = [oct, nov]
        XCTAssertEqual(PipoJourneyProjection.entries(
            goals: [g], transactions: rows, ownerID: owner,
            period: .month, now: now, calendar: utc
        ).map(\.id), [nov.id])
        XCTAssertEqual(PipoJourneyProjection.entries(
            goals: [g], transactions: rows, ownerID: owner,
            period: .allTime, now: now, calendar: utc
        ).count, 2)
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertFalse(PipoJourneyPeriod.month.contains(
            date(2026, 11, 1, hour: 6), now: now, calendar: la
        ), "October local event must not count as November in LA")
        XCTAssertTrue(PipoJourneyPeriod.month.contains(
            date(2026, 11, 1, hour: 9), now: now, calendar: la
        ))
    }

    func testAllTimeIncludesMoreThanTwelveEventsAndStableTieOrder() {
        let owner = UUID(), g = goal(owner: owner)
        let sameDate = date(2026, 11, 20)
        var rows = (0..<14).map { i in
            entry(goal: g, owner: owner,
                  on: sameDate.addingTimeInterval(Double(i + 1)))
        }
        let lower = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higher = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        rows.append(entry(goal: g, owner: owner, on: sameDate, id: higher))
        rows.append(entry(goal: g, owner: owner, on: sameDate, id: lower))
        let result = PipoJourneyProjection.entries(
            goals: [g], transactions: rows, ownerID: owner,
            period: .allTime, calendar: utc
        )
        XCTAssertEqual(result.count, 16, "All Time must not reuse prefix(12)")
        XCTAssertEqual(result.suffix(2).map(\.id), [lower, higher])
        let groups = PipoJourneyProjection.months(result, calendar: utc)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.count, 16)
    }

    func testMultiCurrencyNeverCreatesSyntheticCombinedBalance() {
        let owner = UUID()
        let usd = goal(owner: owner, code: "USD")
        let idr = goal(owner: owner, code: "IDR")
        let records = PipoJourneyProjection.entries(
            goals: [usd, idr],
            transactions: [
                entry(goal: usd, owner: owner, on: date(2026, 11, 10),
                      code: "USD", minor: 1250, amount: 12.5),
                entry(goal: usd, owner: owner, on: date(2026, 11, 11),
                      code: "USD", minor: 250, amount: 2.5),
                entry(goal: idr, owner: owner, on: date(2026, 11, 12),
                      code: "IDR", minor: 900, amount: 900),
            ],
            ownerID: owner, calendar: utc
        )
        let totals = PipoJourneyProjection.exactTotals(records)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals.first(where: { $0.code == "USD" })?.minor, 1500)
        XCTAssertEqual(totals.first(where: { $0.code == "IDR" })?.minor, 900)
        XCTAssertEqual(PipoJourneyProjection.totalEarnedXP(records), 900)
        let broken = entry(goal: usd, owner: owner, on: date(2026, 11, 13),
                           code: "USD", minor: nil, amount: .nan)
        let invalid = PipoJourneyProjection.entries(
            goals: [usd, idr], transactions: [broken] + records.map(\.transaction),
            ownerID: owner, calendar: utc
        )
        XCTAssertTrue(PipoJourneyProjection.exactTotals(invalid).isEmpty,
                      "Never display a partial or invented total with corrupt rows")
    }

    func testOwnerFilterAndTimelineNeverAlterActualXPOrBadgeState() {
        let owner = UUID()
        let g = goal(owner: owner)
        let profile = UserProfile(userID: owner, totalXP: 1_500)
        let savedBadgeIDs = profile.unlockedBadgeIds
        let transaction = entry(goal: g, owner: owner, on: date(2026, 11, 10))
        let originalAmount = g.currentAmount
        _ = PipoJourneyProjection.entries(
            goals: [g], transactions: [transaction], ownerID: owner,
            calendar: utc
        )
        XCTAssertEqual(g.currentAmount, originalAmount)
        XCTAssertEqual(profile.totalXP, 1_500)
        XCTAssertEqual(profile.unlockedBadgeIds, savedBadgeIDs)
    }
}
