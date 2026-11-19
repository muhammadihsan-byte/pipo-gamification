import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionManager {
    static let freePersonalSlots = 1
    static let freeGroupSlots = 1

    private(set) var purchasedPersonalSlots: Int
    private(set) var purchasedGroupSlots: Int
    private(set) var activeUserID: UUID?

    init(purchasedPersonalSlots: Int = 0, purchasedGroupSlots: Int = 0) {
        self.purchasedPersonalSlots = max(purchasedPersonalSlots, 0)
        self.purchasedGroupSlots = max(purchasedGroupSlots, 0)
        activeUserID = nil
    }

    /// Clear displayed purchase allowances whenever the signed-in account changes.
    func switchAccount(to userID: UUID?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        purchasedPersonalSlots = 0
        purchasedGroupSlots = 0
    }

    func canCreateGoal(isGroup: Bool, activeCount: Int) -> Bool {
        let freeSlots = isGroup ? Self.freeGroupSlots : Self.freePersonalSlots
        let purchasedSlots = isGroup ? purchasedGroupSlots : purchasedPersonalSlots
        return max(activeCount, 0) < freeSlots + purchasedSlots
    }

    func updateEntitlements(
        purchasedPersonalSlots: Int,
        purchasedGroupSlots: Int
    ) {
        self.purchasedPersonalSlots = max(purchasedPersonalSlots, 0)
        self.purchasedGroupSlots = max(purchasedGroupSlots, 0)
    }

    func updateEntitlements(
        purchasedPersonalSlots: Int,
        purchasedGroupSlots: Int,
        for userID: UUID
    ) {
        guard activeUserID == userID else { return }
        updateEntitlements(
            purchasedPersonalSlots: purchasedPersonalSlots,
            purchasedGroupSlots: purchasedGroupSlots
        )
    }
}
