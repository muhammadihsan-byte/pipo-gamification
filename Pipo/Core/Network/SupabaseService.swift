import Foundation
import Supabase

struct SupabaseConfiguration: Sendable {
    let url: URL
    let anonKey: String
    let redirectURL: URL

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> SupabaseConfiguration {
        guard let urlValue = configuredValue(
            "SUPABASE_URL",
            environment: environment,
            infoDictionary: infoDictionary
        ) else {
            throw SupabaseConfigurationError.missingURL
        }
        guard
            let url = URL(string: urlValue),
            let scheme = url.scheme?.lowercased(),
            let host = url.host,
            scheme == "https" || (scheme == "http" && isLocalHost(host))
        else {
            throw SupabaseConfigurationError.invalidURL
        }
        guard let anonKey = configuredValue(
            "SUPABASE_ANON_KEY",
            environment: environment,
            infoDictionary: infoDictionary
        ) else {
            throw SupabaseConfigurationError.missingAnonKey
        }

        let redirectValue = configuredValue(
            "SUPABASE_REDIRECT_URL",
            environment: environment,
            infoDictionary: infoDictionary
        ) ?? "pipo://login-callback"
        guard let redirectURL = URL(string: redirectValue), redirectURL.scheme != nil else {
            throw SupabaseConfigurationError.invalidRedirectURL
        }

        return SupabaseConfiguration(url: url, anonKey: anonKey, redirectURL: redirectURL)
    }

    private static func configuredValue(
        _ key: String,
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> String? {
        let candidates = [environment[key], infoDictionary[key] as? String]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("$(") }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
}

enum SupabaseConfigurationError: LocalizedError {
    case missingURL
    case invalidURL
    case missingAnonKey
    case invalidRedirectURL

    var errorDescription: String? {
        switch self {
        case .missingURL:
            "Set SUPABASE_URL in the app build settings or environment."
        case .invalidURL:
            "SUPABASE_URL must be an HTTPS URL (HTTP is allowed for localhost only)."
        case .missingAnonKey:
            "Set SUPABASE_ANON_KEY in the app build settings or environment."
        case .invalidRedirectURL:
            "SUPABASE_REDIRECT_URL must be a valid URL with a scheme."
        }
    }
}

struct SavingTransactionPayload: Codable, Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let amount: Double
    let xpEarned: Int
    // A PostgREST timestamp must be ISO 8601, not JSONEncoder's numeric Date default.
    let date: String

    init(
        id: UUID,
        goalID: UUID,
        userID: UUID,
        amount: Double,
        xpEarned: Int,
        date: Date
    ) {
        self.id = id
        self.goalID = goalID
        self.userID = userID
        self.amount = amount
        self.xpEarned = xpEarned
        self.date = ISO8601DateFormatter().string(from: date)
    }

    init(transaction: SavingTransaction, userID: UUID) {
        id = transaction.id
        goalID = transaction.goalId
        self.userID = userID
        amount = transaction.amount
        xpEarned = transaction.xpEarned
        date = ISO8601DateFormatter().string(from: transaction.date)
    }

    static func makeBatch(
        from transactions: [SavingTransaction],
        authenticatedUserID: UUID
    ) throws -> [SavingTransactionPayload] {
        guard transactions.allSatisfy({ $0.userID == authenticatedUserID }) else {
            throw SupabaseServiceError.transactionBelongsToAnotherUser
        }
        return transactions.map {
            SavingTransactionPayload(transaction: $0, userID: authenticatedUserID)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case goalID = "goal_id"
        case userID = "user_id"
        case amount
        case xpEarned = "xp_earned"
        case date
    }
}

/// Exact payload for the deployed public.saving_goals schema.
/// Group plans, photos, and legacy ownerless rows are intentionally not
/// transmitted while their authorization/storage model is unfinished.
struct SavingGoalPayload: Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let title: String
    let category: String
    let customCategory: String?
    let targetAmount: Double
    let startDate: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Int?

    init(goal: PersonalGoal, userID: UUID) {
        id = goal.id
        self.userID = userID
        title = goal.title
        category = goal.category.rawValue
        customCategory = goal.customCategory
        targetAmount = goal.targetAmount
        startDate = ISO8601DateFormatter().string(from: goal.startDate)
        targetDate = ISO8601DateFormatter().string(from: goal.targetDate)
        rhythm = goal.rhythm.rawValue
        preferredSavingDay = goal.preferredSavingDay
        plannedContributionOverride = goal.plannedContributionOverride
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, rhythm
        case userID = "user_id"
        case customCategory = "custom_category"
        case targetAmount = "target_amount"
        case startDate = "start_date"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }
}

/// An immutable, validated batch means the remote goal always exists before
/// the matching transaction. Reusing UUID IDs makes retries idempotent.
/// Only account-owned personal plans are eligible for cloud backup.
struct PersonalSavingSyncBatch {
    let goals: [SavingGoalPayload]
    let transactions: [SavingTransactionPayload]

    static func make(
        goals: [PersonalGoal],
        transactions: [SavingTransaction],
        authenticatedUserID: UUID
    ) throws -> PersonalSavingSyncBatch {
        guard goals.allSatisfy({
            $0.ownerUserID == authenticatedUserID && !$0.isGroupGoal
        }) else {
            throw SupabaseServiceError.goalNotOwnedOrNotPersonal
        }
        guard goals.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.title.count <= 120 && $0.targetAmount.isFinite &&
            $0.targetAmount > 0 && $0.targetDate >= $0.startDate &&
            ($0.plannedContributionOverride == nil || $0.plannedContributionOverride! > 0)
        }) else {
            throw SupabaseServiceError.invalidSavingGoal
        }
        let allowedIDs = Set(goals.map(\.id))
        guard transactions.allSatisfy({
            $0.userID == authenticatedUserID &&
            allowedIDs.contains($0.goalId) &&
            $0.amount.isFinite && $0.amount > 0
        }) else {
            throw SupabaseServiceError.invalidOrUnownedTransaction
        }
        return PersonalSavingSyncBatch(
            goals: goals.map { SavingGoalPayload(goal: $0, userID: authenticatedUserID) },
            transactions: try SavingTransactionPayload.makeBatch(
                from: transactions, authenticatedUserID: authenticatedUserID
            )
        )
    }
}

struct GroupGoalProgressUpdate: Codable, Equatable, Sendable {
    let goalID: UUID
    let userID: UUID
    let currentAmount: Double
    let targetAmount: Double
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case userID = "user_id"
        case currentAmount = "current_amount"
        case targetAmount = "target_amount"
        case updatedAt = "updated_at"
    }
}

struct UserProfileSlotBalancePayload: Codable, Equatable, Sendable {
    let userID: UUID
    let purchasedPersonalSlots: Int
    let purchasedGroupSlots: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case purchasedPersonalSlots = "purchased_personal_slots"
        case purchasedGroupSlots = "purchased_group_slots"
    }
}

enum SupabaseServiceError: LocalizedError {
    case notAuthenticated
    case transactionBelongsToAnotherUser
    case profileBelongsToAnotherUser
    case invalidGroupGoalProgress
    case goalNotOwnedOrNotPersonal
    case invalidSavingGoal
    case invalidOrUnownedTransaction

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Sign in before syncing data or broadcasting group progress."
        case .transactionBelongsToAnotherUser:
            "A transaction is not owned by the current account and was not synced."
        case .profileBelongsToAnotherUser:
            "The profile is not owned by the current account and was not synced."
        case .invalidGroupGoalProgress:
            "Group goal progress must contain finite, non-negative amounts."
        case .goalNotOwnedOrNotPersonal:
            "Only goals owned by this account can be backed up. Group plans remain on this device."
        case .invalidSavingGoal:
            "This goal has invalid details and cannot be backed up yet."
        case .invalidOrUnownedTransaction:
            "A saving entry is invalid or does not belong to an owned personal goal."
        }
    }
}

@MainActor
final class SupabaseService {
    let configuration: SupabaseConfiguration

    private let client: SupabaseClient
    private var groupChannels: [UUID: RealtimeChannelV2] = [:]

    init(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: configuration.redirectURL,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    static func fromEnvironment() throws -> SupabaseService {
        SupabaseService(configuration: try SupabaseConfiguration.load())
    }

    func signIn(
        email: String,
        password: String,
        authStateManager: AuthStateManager
    ) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        authStateManager.signIn(userID: session.user.id)
    }

    func signUp(
        email: String,
        password: String,
        authStateManager: AuthStateManager
    ) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: configuration.redirectURL
        )
        guard let session = response.session else { return true }
        authStateManager.signIn(userID: session.user.id)
        return false
    }

    func signInWithOAuth(
        provider: Provider,
        authStateManager: AuthStateManager
    ) async throws {
        let session = try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: configuration.redirectURL
        )
        authStateManager.signIn(userID: session.user.id)
    }

    func signOut(authStateManager: AuthStateManager) async throws {
        try await client.auth.signOut()
        authStateManager.signOut()
    }

    func handleAuthCallback(
        _ url: URL,
        authStateManager: AuthStateManager
    ) async throws {
        let session = try await client.auth.session(from: url)
        authStateManager.signIn(userID: session.user.id)
    }

    func observeAuthStateChanges(using authStateManager: AuthStateManager) async {
        for await (_, session) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            if let session {
                authStateManager.signIn(userID: session.user.id)
            } else {
                authStateManager.signOut()
            }
        }
    }

    /// Fail closed if the authenticated account changes between network calls.
    /// Group plans remain local-only until real membership policies are shipped.
    func syncPersonalSavings(
        goals: [PersonalGoal],
        transactions: [SavingTransaction],
        authenticatedUserID: UUID
    ) async throws {
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SupabaseServiceError.notAuthenticated
        }
        let batch = try PersonalSavingSyncBatch.make(
            goals: goals,
            transactions: transactions,
            authenticatedUserID: authenticatedUserID
        )
        guard !batch.goals.isEmpty else { return }
        // The composite FK requires goals before their saving entries.
        try await upsertGoalPayloads(batch.goals)
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SupabaseServiceError.notAuthenticated
        }
        guard !batch.transactions.isEmpty else { return }
        try await upsertTransactionPayloads(batch.transactions)
    }

    // The Supabase SDK's PostgrestResponse<Void> is not Sendable in Swift 6.
    // Keep that response fully inside nonisolated async helpers returning Void,
    // following the same pattern as the pre-existing transaction writer.
    private nonisolated func upsertGoalPayloads(_ payloads: [SavingGoalPayload]) async throws {
        try await client
            .from("saving_goals")
            .upsert(payloads, onConflict: "id")
            .execute()
    }

    private nonisolated func upsertTransactionPayloads(_ payloads: [SavingTransactionPayload]) async throws {
        try await client
            .from("saving_transactions")
            .upsert(payloads, onConflict: "id")
            .execute()
    }

    // Purchased slot counts are authoritative server state. In particular,
    // the iOS app must never UPSERT public.user_profiles or inflate counters.

    nonisolated func fetchUserProfileSlots(userID: UUID) async throws -> UserProfileSlotBalancePayload? {
        guard client.auth.currentUser?.id == userID else {
            throw SupabaseServiceError.notAuthenticated
        }
        let profiles: [UserProfileSlotBalancePayload] = try await client
            .from("user_profiles")
            .select("user_id,purchased_personal_slots,purchased_group_slots")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    func subscribeToGroupGoalProgress(
        goalID: UUID
    ) async throws -> AsyncThrowingStream<GroupGoalProgressUpdate, Error> {
        if let oldChannel = groupChannels.removeValue(forKey: goalID) {
            await client.removeChannel(oldChannel)
        }
        let channel = client.channel(channelName(for: goalID)) {
            $0.isPrivate = true
            $0.broadcast.acknowledgeBroadcasts = true
        }
        let messages = channel.broadcastStream(event: "progress_update")
        try await channel.subscribeWithError()
        groupChannels[goalID] = channel

        return AsyncThrowingStream { continuation in
            let receiveTask = Task {
                do {
                    for await message in messages {
                        guard let payload = message["payload"] else { continue }
                        let update = try payload.decode(as: GroupGoalProgressUpdate.self)
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
            }
        }
    }

    func broadcastGroupGoalProgress(
        goalID: UUID,
        currentAmount: Double,
        targetAmount: Double
    ) async throws {
        guard
            currentAmount.isFinite,
            currentAmount >= 0,
            targetAmount.isFinite,
            targetAmount >= 0
        else {
            throw SupabaseServiceError.invalidGroupGoalProgress
        }
        guard let userID = client.auth.currentUser?.id else {
            throw SupabaseServiceError.notAuthenticated
        }

        let channel = try await groupProgressChannel(for: goalID)
        let update = GroupGoalProgressUpdate(
            goalID: goalID,
            userID: userID,
            currentAmount: currentAmount,
            targetAmount: targetAmount,
            updatedAt: .now
        )
        try await channel.broadcast(event: "progress_update", message: update)
    }

    func unsubscribeFromGroupGoalProgress(goalID: UUID) async {
        guard let channel = groupChannels.removeValue(forKey: goalID) else { return }
        await client.removeChannel(channel)
    }

    private func groupProgressChannel(for goalID: UUID) async throws -> RealtimeChannelV2 {
        if let channel = groupChannels[goalID], channel.status == .subscribed {
            return channel
        }
        if let channel = groupChannels.removeValue(forKey: goalID) {
            await client.removeChannel(channel)
        }

        let channel = client.channel(channelName(for: goalID)) {
            $0.isPrivate = true
            $0.broadcast.acknowledgeBroadcasts = true
        }
        try await channel.subscribeWithError()
        groupChannels[goalID] = channel
        return channel
    }

    private func channelName(for goalID: UUID) -> String {
        "group-goal:\(goalID.uuidString.lowercased())"
    }
}
