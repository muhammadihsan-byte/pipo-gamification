import Foundation
import SwiftData

@Model
final class SavingTransaction {
    var id: UUID
    var goalId: UUID
    var amount: Double
    var xpEarned: Int
    var date: Date
    var userID: UUID?

    init(
        id: UUID = UUID(),
        goalId: UUID,
        amount: Double,
        xpEarned: Int = 300,
        date: Date = .now,
        userID: UUID? = nil
    ) {
        self.id = id
        self.goalId = goalId
        self.amount = amount
        self.xpEarned = xpEarned
        self.date = date
        self.userID = userID
    }
}
