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
        try review.insertGoal(in: writer)
        try writer.save()

        let reader = ModelContext(container)
        let goal = try XCTUnwrap(reader.fetch(FetchDescriptor<PersonalGoal>()).first)
        XCTAssertEqual(goal.title, "Supplies")
        XCTAssertEqual(goal.categoryTitle, "Studio")
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
