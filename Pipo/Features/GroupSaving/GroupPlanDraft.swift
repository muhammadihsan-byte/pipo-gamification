import Foundation

enum GroupPlanStep: Int, CaseIterable {
    case goal = 1, target, timeline, rules, setup, invitations, review, success

    var title: String {
        switch self {
        case .goal: "Goal"
        case .target: "Target"
        case .timeline: "Timeline"
        case .rules: "Contribution rules"
        case .setup: "Group setup"
        case .invitations: "Invite members"
        case .review: "Review & create"
        case .success: "Group created"
        }
    }
}

enum GroupPlanCategory: String, CaseIterable {
    case travel = "Travel", gadget = "Gadget", home = "Home", education = "Education"
    case event = "Event", emergency = "Emergency Fund", other = "Other"

    var modelCategory: GoalCategory {
        switch self {
        case .travel: .trip
        case .gadget: .gadget
        case .home: .house
        default: .other
        }
    }
}

enum GroupContributionMode: String, Codable, CaseIterable {
    case equal = "Equal Contribution"
    case flexible = "Flexible Contribution"
}

// Device-local planning information. A prepared name carries no membership or delivery status.
struct GroupPlanDetails: Codable, Equatable {
    var groupName: String
    var groupDescription: String
    var goalDescription: String
    var expectedContributors: Int
    var mode: GroupContributionMode
    var checkIn: SavingRhythm?
    var preparedMembers: [String]
    var creatorID: UUID?
}

struct GroupPlanDraft {
    var title = ""
    var category: GroupPlanCategory?
    var customCategory = ""
    var goalDescription = ""
    var goalPhoto: Data?
    var targetText = ""
    var usesBreakdown = false
    var items = [GoalBreakdownDraft()]
    var usesDuration = false
    var months = 9
    let start: Date
    var dateEntry: SavingDateEntry
    var mode = GroupContributionMode.equal
    var expected = "1"
    var rhythm = SavingRhythm.monthly
    var checkIn: SavingRhythm?
    var monthDay: Int
    var weekday: Int
    var groupName = ""
    var groupDescription = ""
    var groupPhoto: Data?
    var preparedMembers: [String] = []
    var inviteLater = false
    let calendar: Calendar

    init(start: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.start = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .month, value: 2, to: self.start) ?? self.start
        dateEntry = SavingDateEntry(end, calendar: calendar)
        monthDay = calendar.component(.day, from: start)
        weekday = calendar.component(.weekday, from: start)
    }

    var categoryTitle: String { category == .other ? customCategory.trimmed : category?.rawValue ?? "" }
    var target: Int? {
        if !usesBreakdown { return PersonalPlanFormatting.parseRupiah(targetText) }
        guard !items.isEmpty else { return nil }
        return items.validBreakdownTotal
    }
    var end: Date? {
        let date = usesDuration ? calendar.date(byAdding: .month, value: months, to: start) : dateEntry.date(in: calendar)
        guard let date, calendar.startOfDay(for: date) > start else { return nil }
        return calendar.startOfDay(for: date)
    }
    var contributors: Int? {
        let value = expected.trimmed
        guard value.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(value), n > 0 else { return nil }
        return n
    }
    var preferredDay: Int? {
        switch rhythm {
        case .monthly: monthDay
        case .weekly, .biWeekly: weekday
        default: nil
        }
    }
    var schedule: PersonalSavingSchedule? {
        guard mode == .equal, let end, let target else { return nil }
        return PersonalSavingSchedule(targetAmount: target, startDate: start, targetDate: end,
                                     rhythm: rhythm, preferredDay: preferredDay, calendar: calendar)
    }
    var estimate: Int? {
        guard let count = schedule?.count, let contributors, let target else { return nil }
        // ceil(ceil(target / count) / contributors), without multiplying large counts.
        let perPeriod = target / count + (target.isMultiple(of: count) ? 0 : 1)
        return perPeriod / contributors + (perPeriod.isMultiple(of: contributors) ? 0 : 1)
    }
    func valid(_ step: GroupPlanStep) -> Bool {
        switch step {
        case .goal: !title.trimmed.isEmpty && !categoryTitle.isEmpty
        case .target: target != nil
        case .timeline: end != nil
        case .rules: contributors != nil && (mode == .flexible || schedule != nil)
        case .setup: !groupName.trimmed.isEmpty
        case .invitations: true
        case .review: GroupPlanStep.allCases.filter { $0.rawValue < GroupPlanStep.review.rawValue }.allSatisfy(valid)
        case .success: false
        }
    }

    mutating func prepareMember(_ input: String) throws {
        guard !input.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@")).trimmed.isEmpty else {
            throw GroupSavingError.emptyMemberName
        }
        var members = [GroupMember(id: "creator", name: "You", role: "Group Admin", status: .accepted)]
        members += preparedMembers.map { GroupMember(name: $0, status: .invited) }
        var plan = GroupSavingPlan(title: title, breakdown: [], members: members)
        let entry = try GroupSavingManager().inviteMember(nameOrHandle: input.trimmed, to: &plan)
        preparedMembers.append(entry.name)
        inviteLater = false
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct GroupPlanNavigation {
    private(set) var step = GroupPlanStep.goal
    private(set) var editing = false

    mutating func edit(_ step: GroupPlanStep) {
        guard self.step == .review, step.rawValue < GroupPlanStep.review.rawValue else { return }
        self.step = step
        editing = true
    }

    mutating func advance(_ draft: GroupPlanDraft) {
        guard step.rawValue < GroupPlanStep.review.rawValue, draft.valid(step) else { return }
        if editing {
            step = GroupPlanStep.allCases.first { $0.rawValue < GroupPlanStep.review.rawValue && !draft.valid($0) } ?? .review
            editing = step != .review
        } else if let next = GroupPlanStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    mutating func back(_ draft: GroupPlanDraft) {
        guard step != .success else { return }
        if editing && draft.valid(.review) {
            step = .review
            editing = false
        } else if let previous = GroupPlanStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    mutating func didSave() {
        if step == .review { step = .success }
    }
}
