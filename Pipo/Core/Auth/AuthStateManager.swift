import Foundation
import Observation
import SwiftData

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

    /// External widget links are untrusted navigation requests, not permission
    /// to record money. A stale link must fail closed for paused, archived or
    /// completed goals, group-only drafts and another account's goals.
    static func canOpenWidgetSavingRequest(_ goal: PersonalGoal, userID: UUID?) -> Bool {
        owns(goal, userID: userID) && !goal.isGroupGoal && goal.canRecordSaving
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


/// Local privacy cleanup is applied only after the trusted backend confirms
/// the Auth account is deleted. Ownerless legacy data stays quarantined:
/// assigning its ownership to the deleted user would be unsafe.
@MainActor
enum AccountDeletionLocalData {
    private static let pendingKey = "pipo.account.deletion.pending.local-cleanup"

    static func markServerDeleted(_ userID: UUID, defaults: UserDefaults = .standard) {
        var ids = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        ids.insert(userID.uuidString.lowercased())
        defaults.set(ids.sorted(), forKey: pendingKey)
    }

    static func complete(
        for userID: UUID,
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws {
        // Local deletion is forbidden until the backend reported success.
        guard (defaults.stringArray(forKey: pendingKey) ?? []).contains(
            userID.uuidString.lowercased()
        ) else {
            throw AccountDeletionLocalError.serverDeletionNotConfirmed
        }
        let transactions = try context.fetch(FetchDescriptor<SavingTransaction>())
        let goals = try context.fetch(FetchDescriptor<PersonalGoal>())
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())

        for transaction in transactions where transaction.userID == userID {
            context.delete(transaction)
        }
        for goal in goals where goal.ownerUserID == userID {
            context.delete(goal) // SwiftData cascades to this goal's subitems.
        }
        for profile in profiles where profile.userID == userID {
            context.delete(profile)
        }
        try context.save()
        OnboardingProfileStore.delete(for: userID, in: defaults)

        var ids = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        ids.remove(userID.uuidString.lowercased())
        defaults.set(ids.sorted(), forKey: pendingKey)
    }

    /// A failed device write is retried at next launch without ever contacting
    /// the deleted account or deleting another owner's data.
    static func retryPending(in context: ModelContext, defaults: UserDefaults = .standard) {
        let pending = defaults.stringArray(forKey: pendingKey) ?? []
        for raw in pending {
            guard let userID = UUID(uuidString: raw) else { continue }
            try? complete(for: userID, in: context, defaults: defaults)
        }
    }
}

enum AccountDeletionLocalError: LocalizedError {
    case serverDeletionNotConfirmed

    var errorDescription: String? {
        "The server has not confirmed account deletion. Local data is preserved."
    }
}
