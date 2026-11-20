import Foundation
import Observation

enum AuthState: Equatable, Sendable {
    case unauthenticated
    case authenticated
}

@MainActor
@Observable
final class AuthStateManager {
    private(set) var authState: AuthState
    private(set) var userID: UUID?

    init(initialState: AuthState = .unauthenticated, userID: UUID? = nil) {
        authState = initialState
        self.userID = userID
    }

    func signIn(userID: UUID? = nil) {
        authState = .authenticated
        self.userID = userID
    }

    func signOut() {
        authState = .unauthenticated
        userID = nil
    }
}


/// Account ownership policy for device-local SwiftData records.
/// Historical ownerless rows are preserved (not deleted or auto-claimed) and
/// deliberately remain inaccessible to every authenticated account.
enum AccountScope {
    static func owns(_ goal: PersonalGoal, userID: UUID?) -> Bool {
        guard let userID else { return false }
        return goal.ownerUserID == userID
    }

    static func visibleGoals(_ goals: [PersonalGoal], userID: UUID?) -> [PersonalGoal] {
        goals.filter { owns($0, userID: userID) }
    }

    static func visibleTransactions(
        _ transactions: [SavingTransaction],
        goals: [PersonalGoal],
        userID: UUID?
    ) -> [SavingTransaction] {
        guard let userID else { return [] }
        let ownedGoalIDs = Set(visibleGoals(goals, userID: userID).map(\.id))
        return transactions.filter {
            $0.userID == userID && ownedGoalIDs.contains($0.goalId)
        }
    }
}
