import XCTest
@testable import SatuSaku

final class GamificationManagerTests: XCTestCase {
    func testRecordingSavingAwardsXPUpdatesProfileAndGoal() async throws {
        try await MainActor.run {
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

    func testInvalidDepositDoesNotChangeProfileOrGoal() async {
        await MainActor.run {
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
