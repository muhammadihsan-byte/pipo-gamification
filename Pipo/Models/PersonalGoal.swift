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
    var createdAt: Date

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
        createdAt: Date = .now
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
        self.createdAt = createdAt
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
