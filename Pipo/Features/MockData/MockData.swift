import Foundation

enum MockData {
    static let authEmail = "pipo@example.com"

    static let savingGoalTitle = "Buy new iPad"
    static let savingGoalTarget = 7_500_000.0
    static let savingStartDate = mockDate(year: 2026, month: 10, day: 25)
    static let savingTargetDate = mockDate(year: 2027, month: 7, day: 25)

    static let groupSavingReview = GroupSavingReviewData(
        title: "Japan Trip 2027",
        category: "Travel",
        targetAmount: 13_000_000,
        groupName: "Sakura Squad",
        visibility: "Private · Invite-only",
        goalDescription: "A trip with friends.",
        groupDescription: "Friends planning our Japan adventure, one step at a time.",
        breakdown: [
            GroupGoalBreakdownItem(id: "flights", title: "Flights", amount: 6_000_000),
            GroupGoalBreakdownItem(id: "hotel", title: "Hotel", amount: 5_000_000),
            GroupGoalBreakdownItem(id: "activities", title: "Activities", amount: 2_000_000)
        ],
        plannedStartDate: mockDate(year: 2026, month: 10, day: 25),
        targetDate: mockDate(year: 2027, month: 7, day: 25),
        contributionCount: 10,
        contributionMode: "Equal Contribution",
        rhythm: "Monthly · on the 25th",
        members: [
            GroupReviewMember(id: "you", name: "You", role: "Group Admin", status: .accepted),
            GroupReviewMember(id: "member-2", name: "Member 2", role: "Squad member", status: .invited),
            GroupReviewMember(id: "member-3", name: "Member 3", role: "Squad member", status: .invited),
            GroupReviewMember(id: "member-4", name: "Member 4", role: "Squad member", status: .invited)
        ]
    )

    static let streakDays = 7

    private static func mockDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        guard let date = Calendar.current.date(from: components) else {
            preconditionFailure("Invalid date in preview mock data")
        }
        return date
    }
}
