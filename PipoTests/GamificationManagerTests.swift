import XCTest
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
