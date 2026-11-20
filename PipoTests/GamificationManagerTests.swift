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
    private func makeGoal() -> PersonalGoal {
        PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 10_000,
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
