import Foundation
import SwiftData

enum GoalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case gadget
    case trip
    case gift
    case debt
    case automotive
    case house
    case other

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

enum SavingRhythm: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case biWeekly
    case monthly
    case flexible

    var id: String { rawValue }
}

enum GoalLifecycleState: String, Codable, CaseIterable, Sendable {
    case active, paused, archived, completed

    var title: String {
        switch self {
        case .active: "In progress"
        case .paused: "Paused"
        case .archived: "Archived"
        case .completed: "Completed"
        }
    }
}

@Model
final class SubItem {
    var id: UUID
    var title: String
    var amount: Double
    var isCompleted: Bool
    var goal: PersonalGoal?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        isCompleted: Bool = false,
        goal: PersonalGoal? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.isCompleted = isCompleted
        self.goal = goal
    }
}

@Model
final class PersonalGoal {
    var id: UUID
    var title: String
    var category: GoalCategory
    var customCategory: String?
    var targetAmount: Double
    var currentAmount: Double
    @Relationship(deleteRule: .cascade, inverse: \SubItem.goal)
    var subItems: [SubItem]
    var startDate: Date
    var targetDate: Date
    var rhythm: SavingRhythm
    var preferredSavingDay: Int?
    var plannedContributionOverride: Int?
    var groupDetails: Data?
    @Attribute(.externalStorage) var goalPhoto: Data?
    @Attribute(.externalStorage) var groupPhoto: Data?
    var isGroupGoal: Bool
    // Optional so older SwiftData rows migrate without being assigned to a new login.
    // A nil owner is quarantined and never displayed until ownership is verified.
    var ownerUserID: UUID?
    var createdAt: Date
    // Optional persistence fields permit lightweight migration from old rows.
    var lifecycleRaw: String?
    var isFocusPreferred: Bool?

    init(
        id: UUID = UUID(),
        title: String,
        category: GoalCategory,
        customCategory: String? = nil,
        targetAmount: Double,
        currentAmount: Double = 0,
        subItems: [SubItem] = [],
        startDate: Date = .now,
        targetDate: Date,
        rhythm: SavingRhythm = .weekly,
        preferredSavingDay: Int? = nil,
        isGroupGoal: Bool = false,
        ownerUserID: UUID? = nil,
        createdAt: Date = .now,
        lifecycleRaw: String? = nil,
        isFocusPreferred: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.customCategory = customCategory
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.subItems = subItems
        self.startDate = startDate
        self.targetDate = targetDate
        self.rhythm = rhythm
        self.preferredSavingDay = preferredSavingDay
        self.isGroupGoal = isGroupGoal
        self.ownerUserID = ownerUserID
        self.createdAt = createdAt
        self.lifecycleRaw = lifecycleRaw
        self.isFocusPreferred = isFocusPreferred
    }

    // Progress determines completion, independent of an earlier paused state.
    // Unrecognized legacy values revert safely to an active goal.
    var lifecycleState: GoalLifecycleState {
        if targetAmount > 0 && currentAmount >= targetAmount { return .completed }
        switch lifecycleRaw {
        case GoalLifecycleState.paused.rawValue: return .paused
        case GoalLifecycleState.archived.rawValue: return .archived
        default: return .active
        }
    }

    var canRecordSaving: Bool { lifecycleState == .active }

    @discardableResult
    func transition(to next: GoalLifecycleState) -> Bool {
        let allowed: Bool
        switch (lifecycleState, next) {
        case (.active, .paused), (.active, .archived),
             (.paused, .active), (.paused, .archived),
             (.archived, .active):
            allowed = true
        default:
            allowed = false
        }
        guard allowed else { return false }
        lifecycleRaw = next == .active ? nil : next.rawValue
        return true
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(currentAmount / targetAmount, 0), 1)
    }

    var categoryTitle: String {
        customCategory ?? category.title
    }

    var remainingAmount: Double {
        max(targetAmount - currentAmount, 0)
    }
}
