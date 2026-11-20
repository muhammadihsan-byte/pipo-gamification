import Foundation
import SwiftData
import XCTest
@testable import Pipo

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

    func testMonthlyScheduleClampsToTheLastDayOfShortMonths() throws {
        let schedule = try XCTUnwrap(PersonalSavingSchedule(
            targetAmount: 100, startDate: date(2027, 2, 1), targetDate: date(2027, 4, 30),
            rhythm: .monthly, preferredDay: 31, calendar: calendar
        ))

        XCTAssertEqual(schedule.firstDate, date(2027, 2, 28))
        XCTAssertEqual(schedule.lastDate, date(2027, 4, 30))
        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule.amount, 34)
    }

    func testBiweeklyScheduleUsesTheChosenWeekdayAndTargetCutoff() throws {
        let schedule = try XCTUnwrap(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 2, 5),
            rhythm: .biWeekly, preferredDay: 2, calendar: calendar
        ))

        XCTAssertEqual(schedule.firstDate, date(2027, 1, 11))
        XCTAssertEqual(schedule.lastDate, date(2027, 1, 25))
        XCTAssertEqual(schedule.count, 2)
        XCTAssertEqual(schedule.amount, 450)
    }

    func testShortTimelineAndFlexibleRhythmHaveNoSchedule() {
        XCTAssertNil(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 1, 10),
            rhythm: .weekly, preferredDay: 2, calendar: calendar
        ))
        XCTAssertNil(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 2, 5),
            rhythm: .flexible, preferredDay: nil, calendar: calendar
        ))
    }

    func testRupiahInputsAcceptIndonesianGroupSeparators() {
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("7.500.000"), 7_500_000)
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("Rp 7.500.000"), 7_500_000)
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("7500000"), 7_500_000)
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("7.50"))
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("0"))
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("-100"))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

extension PersonalGoalTests {

    @MainActor
    func testAccountSwitchShowsOnlyOwnedGoalsAndTransactions() throws {
        let accountA = UUID()
        let accountB = UUID()
        let container = try ModelContainer(
            for: Schema([PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let goalA = PersonalGoal(title: "Private A", category: .trip,
                                 targetAmount: 1_000, targetDate: .now,
                                 ownerUserID: accountA)
        let goalB = PersonalGoal(title: "Private B", category: .gadget,
                                 targetAmount: 2_000, targetDate: .now,
                                 ownerUserID: accountB)
        let oldGoal = PersonalGoal(title: "Legacy unowned", category: .trip,
                                   targetAmount: 3_000, targetDate: .now)
        context.insert(goalA)
        context.insert(goalB)
        context.insert(oldGoal)
        context.insert(SavingTransaction(goalId: goalA.id, amount: 100, userID: accountA))
        context.insert(SavingTransaction(goalId: goalB.id, amount: 200, userID: accountB))
        // A transaction may claim B in its metadata, but still points at A's goal.
        context.insert(SavingTransaction(goalId: goalA.id, amount: 999, userID: accountB))
        context.insert(SavingTransaction(goalId: oldGoal.id, amount: 444, userID: nil))
        try context.save()

        let reopened = ModelContext(container)
        let goals = try reopened.fetch(FetchDescriptor<PersonalGoal>())
        let entries = try reopened.fetch(FetchDescriptor<SavingTransaction>())
        XCTAssertEqual(Set(AccountScope.visibleGoals(goals, userID: accountA).map(\.id)), [goalA.id])
        XCTAssertEqual(Set(AccountScope.visibleGoals(goals, userID: accountB).map(\.id)), [goalB.id])
        XCTAssertTrue(AccountScope.visibleGoals(goals, userID: nil).isEmpty)
        XCTAssertEqual(AccountScope.visibleTransactions(entries, goals: goals, userID: accountA).map(\.amount), [100])
        XCTAssertEqual(AccountScope.visibleTransactions(entries, goals: goals, userID: accountB).map(\.amount), [200])
        XCTAssertTrue(AccountScope.visibleTransactions(entries, goals: goals, userID: nil).isEmpty)

        // Legacy records remain on disk/in the store and are never silently claimed.
        XCTAssertEqual(goals.count, 3)
        XCTAssertNil(try XCTUnwrap(goals.first(where: { $0.id == oldGoal.id })).ownerUserID)
        XCTAssertEqual(entries.count, 4)
    }

    @MainActor
    func testUnownedLegacyProfileIsNotAdoptedOnNextSignIn() throws {
        let accountA = UUID()
        let accountB = UUID()
        let legacy = UserProfile(totalXP: 5_000, unlockedBadgeIds: ["private-badge"])
        let owned = UserProfile(userID: accountA, totalXP: 80)
        let profiles = [legacy, owned]
        XCTAssertEqual(UserProfile.existing(for: accountA, in: profiles)?.id, owned.id)
        XCTAssertNil(UserProfile.existing(for: accountB, in: profiles))
        XCTAssertNil(UserProfile.existing(for: nil, in: profiles))
        XCTAssertNil(legacy.userID)
    }

    func testWidgetSnapshotsAreHiddenAcrossAccountSwitchAndLogout() throws {
        let suite = "pipo.widget.account-scope.qa.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = UUID()
        let accountB = UUID()
        let goalID = UUID()
        let snapshot = WidgetSnapshot(
            streakDays: 2, totalXP: 600, currentLevel: 1,
            goalID: goalID, goalTitle: "Private savings",
            goalProgress: 0.4, nextDepositDate: nil, ownerUserID: accountA
        )

        WidgetSharedData.activate(userID: accountA, in: defaults)
        try WidgetSharedData.save(snapshot, in: defaults)
        XCTAssertEqual(WidgetSharedData.load(from: defaults).goalID, goalID)

        WidgetSharedData.activate(userID: accountB, in: defaults)
        XCTAssertNil(WidgetSharedData.load(from: defaults).goalID)
        XCTAssertThrowsError(try WidgetSharedData.save(snapshot, in: defaults))

        // An upgrade can encounter a legacy snapshot without an owner tag.
        defaults.set(["goalID": goalID.uuidString, "goalTitle": "Old savings"],
                     forKey: "pipo.widget.snapshot")
        XCTAssertNil(WidgetSharedData.load(from: defaults).goalTitle)

        WidgetSharedData.activate(userID: nil, in: defaults)
        XCTAssertEqual(WidgetSharedData.load(from: defaults).totalXP, 0)
    }

    @MainActor
    func testGroupReviewPersistsLocalMetadataAndSingleTargetWithoutMockRows() throws {
        var draft = GroupPlanDraft()
        draft.title = "Supplies"
        draft.category = .other
        draft.customCategory = "Studio"
        draft.groupName = "Art club"
        draft.targetText = "1.250.000"
        draft.mode = .flexible
        draft.checkIn = .weekly
        try draft.prepareMember("Ari")
        let owner = UUID()
        let review = try XCTUnwrap(draft.review(creatorID: owner))
        let schema = Schema([PersonalGoal.self, SubItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let writer = ModelContext(container)
        try review.insertGoal(in: writer, ownerUserID: owner)
        try writer.save()

        let reader = ModelContext(container)
        let goal = try XCTUnwrap(reader.fetch(FetchDescriptor<PersonalGoal>()).first)
        XCTAssertEqual(goal.title, "Supplies")
        XCTAssertEqual(goal.categoryTitle, "Studio")
        XCTAssertEqual(goal.ownerUserID, owner)
        XCTAssertEqual(goal.rhythm, .flexible)
        XCTAssertEqual(goal.targetAmount, 1_250_000)
        XCTAssertTrue(goal.subItems.isEmpty)
        XCTAssertTrue(goal.isGroupGoal)
        let details = try JSONDecoder().decode(GroupPlanDetails.self, from: XCTUnwrap(goal.groupDetails))
        XCTAssertEqual(details.groupName, "Art club")
        XCTAssertEqual(details.checkIn, .weekly)
        XCTAssertEqual(details.creatorID, owner)
        XCTAssertEqual(details.preparedMembers, ["Ari"])
        XCTAssertEqual(review.members.map(\.status), [.accepted])
    }
}
