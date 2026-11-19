import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var userID: UUID?
    var totalXP: Int
    var currentLevel: Int
    var streakDays: Int
    var lastSavingDate: Date?
    var unlockedBadgeIds: [String]
    var isPremium: Bool
    var activePersonalGoalsCount: Int
    var activeGroupGoalsCount: Int
    var purchasedPersonalSlots: Int = 0
    var purchasedGroupSlots: Int = 0
    var processedStoreKitTransactionIDs: [String] = []

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        totalXP: Int = 0,
        currentLevel: Int = 1,
        streakDays: Int = 0,
        lastSavingDate: Date? = nil,
        unlockedBadgeIds: [String] = [],
        isPremium: Bool = false,
        activePersonalGoalsCount: Int = 0,
        activeGroupGoalsCount: Int = 0,
        purchasedPersonalSlots: Int = 0,
        purchasedGroupSlots: Int = 0,
        processedStoreKitTransactionIDs: [String] = []
    ) {
        self.id = id
        self.userID = userID
        self.totalXP = totalXP
        self.currentLevel = currentLevel
        self.streakDays = streakDays
        self.lastSavingDate = lastSavingDate
        self.unlockedBadgeIds = unlockedBadgeIds
        self.isPremium = isPremium
        self.activePersonalGoalsCount = activePersonalGoalsCount
        self.activeGroupGoalsCount = activeGroupGoalsCount
        self.purchasedPersonalSlots = purchasedPersonalSlots
        self.purchasedGroupSlots = purchasedGroupSlots
        self.processedStoreKitTransactionIDs = processedStoreKitTransactionIDs
    }

    static func existing(for userID: UUID?, in profiles: [UserProfile]) -> UserProfile? {
        guard let userID else { return nil }
        return profiles.first(where: { $0.userID == userID })
    }
}
