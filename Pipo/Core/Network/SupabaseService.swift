import Foundation
import Supabase

/// Social providers are intentionally not offered until Apple token
/// revocation, credentials and real-device provider QA are all complete.
enum AuthProviderAvailability {
    static let socialSignInEnabled = false
}

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

    /// Use a distinct callback path so password recovery never
    /// silently becomes a normal sign-in.
    var passwordRecoveryRedirectURL: URL {
        redirectURL.appendingPathComponent("reset-password")
    }

    func isSignInCallback(_ url: URL) -> Bool {
        matchesCallback(url, expected: redirectURL)
    }

    func isPasswordRecoveryCallback(_ url: URL) -> Bool {
        matchesCallback(url, expected: passwordRecoveryRedirectURL)
    }

    private func matchesCallback(_ url: URL, expected: URL) -> Bool {
        url.scheme?.lowercased() == expected.scheme?.lowercased()
            && url.host?.lowercased() == expected.host?.lowercased()
            && url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == expected.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

struct SavingTransactionPayload: Encodable, Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let amount: Double // legacy display/test compatibility; never used for wire encoding
    let xpEarned: Int
    let date: String
    private let wireAmount: Decimal

    init(id: UUID, goalID: UUID, userID: UUID,
         amount: Double, xpEarned: Int, date: Date) {
        self.id = id
        self.goalID = goalID
        self.userID = userID
        self.amount = amount
        wireAmount = Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) ?? 0
        self.xpEarned = xpEarned
        self.date = ISO8601DateFormatter().string(from: date)
    }

    init(transaction: SavingTransaction, userID: UUID) {
        id = transaction.id
        goalID = transaction.goalId
        self.userID = userID
        amount = transaction.amount
        wireAmount = transaction.amountMinorUnits.map {
            PipoGoalCurrency.decimal($0, code: transaction.currencyCode ?? "IDR")
        } ?? Decimal(string: String(transaction.amount), locale: Locale(identifier: "en_US_POSIX")) ?? 0
        xpEarned = transaction.xpEarned
        date = ISO8601DateFormatter().string(from: transaction.date)
    }

    static func makeBatch(from transactions: [SavingTransaction],
                          authenticatedUserID: UUID) throws -> [SavingTransactionPayload] {
        guard transactions.allSatisfy({ $0.userID == authenticatedUserID })
        else { throw SupabaseServiceError.transactionBelongsToAnotherUser }
        // Two local rows with a reused UUID are ambiguous, even when their
        // goal and amount appear identical. Fail the complete upload batch.
        // Do not let Postgres ON CONFLICT choose which entry becomes canonical.
        guard Set(transactions.map(\.id)).count == transactions.count else {
            throw SupabaseServiceError.invalidOrUnownedTransaction
        }
        return transactions.map { SavingTransactionPayload(transaction: $0, userID: authenticatedUserID) }
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, date
        case goalID = "goal_id"
        case userID = "user_id"
        case xpEarned = "xp_earned"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(goalID, forKey: .goalID)
        try c.encode(userID, forKey: .userID)
        try c.encode(wireAmount, forKey: .amount)
        try c.encode(xpEarned, forKey: .xpEarned)
        try c.encode(date, forKey: .date)
    }
}

/// Exact numeric payload for public.saving_goals. The currency is per goal,
/// never a mutable account-wide preference, and PostgREST receives a Decimal.
struct SavingGoalPayload: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let title: String
    let category: String
    let customCategory: String?
    let targetAmount: Double // legacy test/view compatibility
    let currencyCode: String
    let startDate: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Int?
    private let wireTarget: Decimal

    init(goal: PersonalGoal, userID: UUID) {
        id = goal.id
        self.userID = userID
        title = goal.title
        category = goal.category.rawValue
        customCategory = goal.customCategory
        targetAmount = goal.targetAmount
        currencyCode = goal.effectiveCurrencyCode
        wireTarget = goal.exactTargetMinor.map {
            PipoGoalCurrency.decimal($0, code: goal.effectiveCurrencyCode)
        } ?? Decimal(string: String(goal.targetAmount), locale: Locale(identifier: "en_US_POSIX")) ?? 0
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
        case currencyCode = "currency_code"
        case startDate = "start_date"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(customCategory, forKey: .customCategory)
        try c.encode(wireTarget, forKey: .targetAmount)
        try c.encode(currencyCode, forKey: .currencyCode)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(targetDate, forKey: .targetDate)
        try c.encode(rhythm, forKey: .rhythm)
        try c.encodeIfPresent(preferredSavingDay, forKey: .preferredSavingDay)
        if let plannedContributionOverride {
            // The local schedule stores minor units; Postgres numeric(15,2)
            // stores major currency units, never a cent count.
            try c.encode(PipoGoalCurrency.decimal(
                Int64(plannedContributionOverride), code: currencyCode
            ), forKey: .plannedContributionOverride)
        }
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
        // Duplicate identifiers must fail closed, not trap in a Dictionary
        // initializer while preparing an authenticated sync batch.
        guard allowedIDs.count == goals.count else {
            throw SupabaseServiceError.invalidSavingGoal
        }
        let byGoal = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        guard goals.allSatisfy({
            PipoGoalCurrency.isSupported($0.effectiveCurrencyCode) &&
            ($0.effectiveCurrencyCode == "IDR" || $0.targetMinorUnits != nil) &&
            ($0.exactTargetMinor ?? 0) > 0 &&
            PipoGoalCurrency.legacyMinor(
                $0.targetAmount, code: $0.effectiveCurrencyCode
            ) == $0.exactTargetMinor
        }) else { throw SupabaseServiceError.invalidSavingGoal }
        guard transactions.allSatisfy({ tx in
            guard tx.userID == authenticatedUserID,
                  allowedIDs.contains(tx.goalId),
                  let goal = byGoal[tx.goalId], tx.amount.isFinite, tx.amount > 0
            else { return false }
            let code = goal.effectiveCurrencyCode
            guard tx.currencyCode == nil || tx.currencyCode == code else { return false }
            if code != "IDR" && tx.amountMinorUnits == nil { return false }
            let parsed = PipoGoalCurrency.legacyMinor(tx.amount, code: code)
            let minor = tx.amountMinorUnits ?? parsed ?? 0
            return minor > 0 && parsed == minor
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

/// Rows are decoded from an account-restricted Supabase SELECT only.
/// The server uses numeric(18,2); the app requires exact whole IDR amounts
/// until fractional-currency support is formally designed.
struct SavingLedgerCloudContribution: Decodable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let amount: Double
    let xpEarned: Int
    let date: String

    enum CodingKeys: String, CodingKey {
        case id, amount, date
        case goalID = "goal_id"
        case userID = "user_id"
        case xpEarned = "xp_earned"
    }
}

struct SavingLedgerCloudAdjustment: Decodable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let kind: String
    let amount: Double
    let correctsEventID: UUID?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, amount
        case goalID = "goal_id"
        case userID = "user_id"
        case correctsEventID = "corrects_event_id"
        case createdAt = "created_at"
    }
}

// MARK: - #80: Inactive, server-revisioned Manage Plan contract
//
// Prepared for the staged CAS backend, but deliberately NOT wired to a
// production Supabase RPC or to any Manage Plan Save button. Current
// goal-first UPSERT is incompatible with the proposed revocation of UPDATE.
// Do not activate until signed-old-client migration and backend review pass.

enum SavingPlanCASContractError: Error, Equatable {
    case invalidRevision
    case invalidGoalAmount
    case invalidSchedule
    case invalidServerResponse
}

/// Owns a stable request UUID across offline retries. Encodes only the
/// allowlisted p_* RPC parameters, never a user_id or currency override.
/// Target and future contribution use exact Decimal major units, not Double.
struct SavingPlanCASRequest: Encodable, Equatable, Sendable {
    let requestID: UUID
    let goalID: UUID
    let expectedRevision: Int64
    let targetAmount: Decimal
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?

    // Local-only evidence used to validate the server's immutable goal code.
    // This MUST NOT be sent to the RPC as a currency-setting argument.
    let currencyCode: String

    init(
        requestID: UUID, goalID: UUID, expectedRevision: Int64,
        targetMinorUnits: Int64, currencyCode: String, targetDate: Date,
        rhythm: String, preferredSavingDay: Int?,
        plannedContributionMinorUnits: Int64?
    ) throws {
        guard expectedRevision >= 0 && expectedRevision < Int64.max else {
            throw SavingPlanCASContractError.invalidRevision
        }
        guard PipoGoalCurrency.isSupported(currencyCode) &&
                currencyCode == currencyCode.uppercased(),
              targetMinorUnits > 0
        else { throw SavingPlanCASContractError.invalidGoalAmount }
        let target = PipoGoalCurrency.decimal(targetMinorUnits, code: currencyCode)
        guard PipoGoalCurrency.minorUnits(target, code: currencyCode) == targetMinorUnits
        else { throw SavingPlanCASContractError.invalidGoalAmount }

        let cadence = ["daily", "weekly", "biWeekly", "monthly", "flexible"]
        guard cadence.contains(rhythm), targetDate.timeIntervalSince1970.isFinite,
              (preferredSavingDay == nil || (1...31).contains(preferredSavingDay!)),
              (rhythm != "daily" && rhythm != "flexible" || preferredSavingDay == nil),
              (rhythm != "weekly" && rhythm != "biWeekly"
                || preferredSavingDay == nil || preferredSavingDay! <= 7),
              (rhythm != "flexible" || plannedContributionMinorUnits == nil)
        else { throw SavingPlanCASContractError.invalidSchedule }

        let contribution: Decimal?
        if let plannedContributionMinorUnits {
            guard plannedContributionMinorUnits > 0 else {
                throw SavingPlanCASContractError.invalidGoalAmount
            }
            let amount = PipoGoalCurrency.decimal(
                plannedContributionMinorUnits, code: currencyCode
            )
            guard PipoGoalCurrency.minorUnits(amount, code: currencyCode)
                    == plannedContributionMinorUnits else {
                throw SavingPlanCASContractError.invalidGoalAmount
            }
            contribution = amount
        } else {
            contribution = nil
        }

        self.requestID = requestID
        self.goalID = goalID
        self.expectedRevision = expectedRevision
        self.targetAmount = target
        self.targetDate = ISO8601DateFormatter().string(from: targetDate)
        self.rhythm = rhythm
        self.preferredSavingDay = preferredSavingDay
        self.plannedContributionOverride = contribution
        self.currencyCode = currencyCode
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case goalID = "p_goal_id"
        case expectedRevision = "p_expected_revision"
        case targetAmount = "p_target_amount"
        case targetDate = "p_target_date"
        case rhythm = "p_rhythm"
        case preferredSavingDay = "p_preferred_saving_day"
        case plannedContributionOverride = "p_planned_contribution_override"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(goalID, forKey: .goalID)
        try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(targetAmount, forKey: .targetAmount)
        try c.encode(targetDate, forKey: .targetDate)
        try c.encode(rhythm, forKey: .rhythm)
        // The SQL function requires all nullable arguments to be present.
        try c.encode(preferredSavingDay, forKey: .preferredSavingDay)
        try c.encode(plannedContributionOverride, forKey: .plannedContributionOverride)
    }
}

struct SavingPlanCASWireResponse: Decodable, Sendable {
    let status: String
    let goalID: UUID
    let requestID: UUID?
    let acceptedRevision: Int64?
    let currentRevision: Int64?
    let currencyCode: String?
    let targetAmount: Decimal?
    let targetDate: String?
    let rhythm: String?
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?

    enum CodingKeys: String, CodingKey {
        case status, rhythm
        case goalID = "goal_id"
        case requestID = "request_id"
        case acceptedRevision = "accepted_revision"
        case currentRevision = "current_revision"
        case currencyCode = "currency_code"
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }
}

/// This result NEVER writes SwiftData, XP, saving entries, or achievements.
/// A verified applied receipt is not necessarily the most recent plan:
/// a later successful edit may follow an idempotent replay of an older UUID.
enum SavingPlanCASOutcome: Equatable, Sendable {
    case applied(requestID: UUID, acceptedRevision: Int64)
    case conflict(currentRevision: Int64)
}

enum SavingPlanCASReceiptValidator {
    static func verify(
        _ response: SavingPlanCASWireResponse,
        for request: SavingPlanCASRequest
    ) throws -> SavingPlanCASOutcome {
        guard response.goalID == request.goalID else {
            throw SavingPlanCASContractError.invalidServerResponse
        }
        if response.status == "conflict" {
            guard let current = response.currentRevision,
                  current >= 0 && current != request.expectedRevision,
                  response.requestID == nil, response.acceptedRevision == nil,
                  response.currencyCode == nil, response.targetAmount == nil,
                  response.targetDate == nil
            else { throw SavingPlanCASContractError.invalidServerResponse }
            return .conflict(currentRevision: current)
        }
        guard response.status == "applied",
              response.requestID == request.requestID,
              response.currentRevision == nil,
              response.acceptedRevision == request.expectedRevision + 1,
              response.currencyCode == request.currencyCode,
              response.targetAmount == request.targetAmount,
              response.rhythm == request.rhythm,
              response.preferredSavingDay == request.preferredSavingDay,
              response.plannedContributionOverride == request.plannedContributionOverride,
              let date = response.targetDate
        else { throw SavingPlanCASContractError.invalidServerResponse }

        // PostgreSQL JSON timestamps can have a timezone offset and/or
        // fractional seconds. Compare the instant, not its textual timezone.
        let whole = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let reported = fractional.date(from: date) ?? whole.date(from: date),
              let requested = whole.date(from: request.targetDate),
              abs(reported.timeIntervalSince1970 - requested.timeIntervalSince1970) < 0.001
        else { throw SavingPlanCASContractError.invalidServerResponse }

        return .applied(
            requestID: request.requestID,
            acceptedRevision: request.expectedRevision + 1
        )
    }
}

// MARK: - #80: Dormant *atomic* target + budget CAS V2 wire contract
//
// V1 does not synchronize SwiftData SubItem. This V2 request is a distinct,
// currently UNWIRED protocol: it replaces target, schedule and complete
// ordered budget in one authenticated RPC transaction. It never sends user_id,
// goal currency, ledger history or XP. No production call site uses this.

enum SavingPlanBudgetV2ContractError: Error, Equatable {
    case invalidPlan
    case invalidBudget
    case userReviewRequired
    case invalidServerResponse
}

struct SavingPlanBudgetV2Item: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let amount: Decimal
    let isCompleted: Bool

    init(id: UUID, title: String, minorUnits: Int64,
         currencyCode: String, isCompleted: Bool) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, minorUnits > 0,
              PipoGoalCurrency.isSupported(currencyCode),
              PipoGoalCurrency.minorUnits(
                PipoGoalCurrency.decimal(minorUnits, code: currencyCode),
                code: currencyCode
              ) == minorUnits
        else { throw SavingPlanBudgetV2ContractError.invalidBudget }
        self.id = id
        self.title = name
        amount = PipoGoalCurrency.decimal(minorUnits, code: currencyCode)
        self.isCompleted = isCompleted
    }

    enum CodingKeys: String, CodingKey {
        case id, title, amount
        case isCompleted = "is_completed"
    }
}

struct SavingPlanBudgetV2Request: Encodable, Equatable, Sendable {
    let requestID: UUID
    let goalID: UUID
    let expectedRevision: Int64
    let expectedOwnerID: UUID // local Auth guard only, NEVER transmitted.
    let currencyCode: String  // immutable existing goal, NEVER transmitted.
    let targetAmount: Decimal
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?
    let items: [SavingPlanBudgetV2Item]
    let budgetImportConfirmed: Bool

    init(requestID: UUID, goalID: UUID, expectedRevision: Int64,
         ownerID: UUID, currencyCode: String, targetMinorUnits: Int64,
         targetDate: Date, rhythm: String, preferredSavingDay: Int?,
         plannedContributionMinorUnits: Int64?,
         items: [SavingPlanBudgetV2Item],
         cloudBudgetNeedsReview: Bool, userReviewedBudget: Bool) throws {
        guard expectedRevision >= 0 && expectedRevision < Int64.max,
              currencyCode == currencyCode.uppercased(),
              PipoGoalCurrency.isSupported(currencyCode),
              targetMinorUnits > 0,
              PipoGoalCurrency.minorUnits(
                PipoGoalCurrency.decimal(targetMinorUnits, code: currencyCode),
                code: currencyCode
              ) == targetMinorUnits,
              targetDate.timeIntervalSince1970.isFinite,
              ["daily", "weekly", "biWeekly", "monthly", "flexible"].contains(rhythm),
              preferredSavingDay == nil || (1...31).contains(preferredSavingDay!),
              (rhythm != "daily" && rhythm != "flexible"
                || preferredSavingDay == nil),
              (rhythm != "weekly" && rhythm != "biWeekly"
                || preferredSavingDay == nil || preferredSavingDay! <= 7),
              (rhythm != "flexible" || plannedContributionMinorUnits == nil)
        else { throw SavingPlanBudgetV2ContractError.invalidPlan }

        if cloudBudgetNeedsReview && !userReviewedBudget {
            throw SavingPlanBudgetV2ContractError.userReviewRequired
        }
        var future: Decimal?
        if let plannedContributionMinorUnits {
            guard plannedContributionMinorUnits > 0,
                  PipoGoalCurrency.minorUnits(
                    PipoGoalCurrency.decimal(
                      plannedContributionMinorUnits, code: currencyCode),
                    code: currencyCode
                  ) == plannedContributionMinorUnits
            else { throw SavingPlanBudgetV2ContractError.invalidPlan }
            future = PipoGoalCurrency.decimal(
                plannedContributionMinorUnits, code: currencyCode
            )
        }

        guard items.count <= 64 else {
            throw SavingPlanBudgetV2ContractError.invalidBudget
        }
        var ids = Set<UUID>()
        var allocated: Int64 = 0
        for item in items {
            guard ids.insert(item.id).inserted,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.title == item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                  item.title.count <= 80,
                  let units = PipoGoalCurrency.minorUnits(
                    item.amount, code: currencyCode
                  ) else { throw SavingPlanBudgetV2ContractError.invalidBudget }
            let (next, overflow) = allocated.addingReportingOverflow(units)
            guard !overflow else { throw SavingPlanBudgetV2ContractError.invalidBudget }
            allocated = next
        }
        guard items.isEmpty || allocated == targetMinorUnits else {
            throw SavingPlanBudgetV2ContractError.invalidBudget
        }
        self.requestID = requestID
        self.goalID = goalID
        self.expectedRevision = expectedRevision
        expectedOwnerID = ownerID
        self.currencyCode = currencyCode
        targetAmount = PipoGoalCurrency.decimal(
            targetMinorUnits, code: currencyCode
        )
        self.targetDate = ISO8601DateFormatter().string(from: targetDate)
        self.rhythm = rhythm
        self.preferredSavingDay = preferredSavingDay
        plannedContributionOverride = future
        self.items = items
        budgetImportConfirmed = userReviewedBudget
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case goalID = "p_goal_id"
        case expectedRevision = "p_expected_revision"
        case targetAmount = "p_target_amount"
        case targetDate = "p_target_date"
        case rhythm = "p_rhythm"
        case preferredSavingDay = "p_preferred_saving_day"
        case plannedContributionOverride = "p_planned_contribution_override"
        case items = "p_items"
        case budgetImportConfirmed = "p_budget_import_confirmed"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(goalID, forKey: .goalID)
        try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(targetAmount, forKey: .targetAmount)
        try c.encode(targetDate, forKey: .targetDate)
        try c.encode(rhythm, forKey: .rhythm)
        try c.encode(preferredSavingDay, forKey: .preferredSavingDay)
        try c.encode(plannedContributionOverride, forKey: .plannedContributionOverride)
        try c.encode(items, forKey: .items)
        try c.encode(budgetImportConfirmed, forKey: .budgetImportConfirmed)
    }
}

struct SavingPlanBudgetV2WireResponse: Decodable, Sendable {
    let status: String
    let requestID: UUID?
    let goalID: UUID?
    let acceptedRevision: Int64?
    let currentRevision: Int64?
    let currencyCode: String?
    let budgetSnapshotState: String?
    let targetAmount: Decimal?
    let targetDate: String?
    let rhythm: String?
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?
    let items: [SavingPlanBudgetV2Item]?

    enum CodingKeys: String, CodingKey {
        case status, rhythm, items
        case requestID = "request_id"
        case goalID = "goal_id"
        case acceptedRevision = "accepted_revision"
        case currentRevision = "current_revision"
        case currencyCode = "currency_code"
        case budgetSnapshotState = "budget_snapshot_state"
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }
}

enum SavingPlanBudgetV2Outcome: Equatable, Sendable {
    case applied(requestID: UUID, revision: Int64)
    case conflict(currentRevision: Int64)
}

enum SavingPlanBudgetV2ReceiptValidator {
    private static func parseDate(_ raw: String) -> Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    /// A receipt alone is NOT proof the goal still matches after later
    /// writes; a freshly authenticated, owner-filtered V2 readback and local
    /// reconciliation are also required before marking this edit complete.
    static func verify(_ response: SavingPlanBudgetV2WireResponse,
                       for request: SavingPlanBudgetV2Request)
        throws -> SavingPlanBudgetV2Outcome {
        guard response.goalID == request.goalID else {
            throw SavingPlanBudgetV2ContractError.invalidServerResponse
        }
        switch response.status {
        case "conflict":
            guard let revision = response.currentRevision,
                  revision >= 0 && revision != request.expectedRevision,
                  response.acceptedRevision == nil,
                  response.items == nil else {
                throw SavingPlanBudgetV2ContractError.invalidServerResponse
            }
            return .conflict(currentRevision: revision)
        case "applied":
            guard response.requestID == request.requestID,
                  response.acceptedRevision == request.expectedRevision + 1,
                  response.currentRevision == nil,
                  response.currencyCode == request.currencyCode,
                  response.budgetSnapshotState == "synced",
                  response.targetAmount == request.targetAmount,
                  response.rhythm == request.rhythm,
                  response.preferredSavingDay == request.preferredSavingDay,
                  response.plannedContributionOverride ==
                    request.plannedContributionOverride,
                  let serverDate = response.targetDate.flatMap(parseDate),
                  let requestedDate = parseDate(request.targetDate),
                  abs(serverDate.timeIntervalSince1970
                        - requestedDate.timeIntervalSince1970) < 0.001,
                  response.items == request.items else {
                throw SavingPlanBudgetV2ContractError.invalidServerResponse
            }
            return .applied(requestID: request.requestID,
                            revision: request.expectedRevision + 1)
        default:
            throw SavingPlanBudgetV2ContractError.invalidServerResponse
        }
    }
}

// MARK: - #80: Budget CAS V2 durable intent + owner-verified readback (DORMANT)
//
// Distinct from the old *target-only* V1 journal. No RPC or UI calls this
// component. An acknowledged RPC is NOT sufficient to resolve a local draft.
// There is intentionally no "finish" method: native SwiftData merge, release
// bridge, authenticated network fetch and owner approval are still required.

enum SavingPlanBudgetV2JournalError: Error, Equatable {
    case invalidJournal
    case accountChanged
    case idempotencyConflict
    case goalAlreadyPending
    case tooManyIntents
    case unknownIntent
    case invalidTransition
    case unverifiedReadback
    case userDecisionRequired
}

struct SavingPlanBudgetV2CloudSnapshot: Decodable, Sendable {
    let status: String
    let goalID: UUID
    let planRevision: Int64
    let currencyCode: String
    let budgetSnapshotState: String
    let targetAmount: Decimal
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?
    let items: [SavingPlanBudgetV2Item]

    enum CodingKeys: String, CodingKey {
        case status, rhythm, items
        case goalID = "goal_id"
        case planRevision = "plan_revision"
        case currencyCode = "currency_code"
        case budgetSnapshotState = "budget_snapshot_state"
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }
}

/// This verifies CONTENT only. Caller must first get the snapshot from a
/// fresh authenticated pipo_read_plan_budget_v2 RPC, checking currentUser
/// equals the expected owner both BEFORE and AFTER the awaited request.
enum SavingPlanBudgetV2SnapshotVerifier {
    static func matchesCurrent(
        _ snapshot: SavingPlanBudgetV2CloudSnapshot,
        request: SavingPlanBudgetV2Request,
        authenticatedOwnerID: UUID
    ) -> Bool {
        let standard = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let serverDate = fractional.date(from: snapshot.targetDate)
                ?? standard.date(from: snapshot.targetDate),
              let wantedDate = standard.date(from: request.targetDate)
        else { return false }
        return authenticatedOwnerID == request.expectedOwnerID
            && snapshot.status == "snapshot"
            && snapshot.goalID == request.goalID
            && snapshot.planRevision == request.expectedRevision + 1
            && snapshot.currencyCode == request.currencyCode
            && snapshot.budgetSnapshotState == "synced"
            && snapshot.targetAmount == request.targetAmount
            && abs(serverDate.timeIntervalSince1970
                   - wantedDate.timeIntervalSince1970) < 0.001
            && snapshot.rhythm == request.rhythm
            && snapshot.preferredSavingDay == request.preferredSavingDay
            && snapshot.plannedContributionOverride
                == request.plannedContributionOverride
            && snapshot.items == request.items
    }
}

struct PendingSavingPlanBudgetV2Intent: Codable, Equatable, Sendable {
    struct StoredItem: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let minorUnits: Int64
        let isCompleted: Bool
    }

    enum State: String, Codable, Sendable {
        case staged          // Original request retained across timeout/relaunch
        case acknowledged    // Receipt checked; still need FRESH cloud read
        case verified        // Cloud read checked; local SwiftData NOT merged
        case conflicted      // Must obtain explicit decision on stale edit
        case discarded       // Durable terminal UUID tombstone after decision
    }

    let ownerID: UUID
    let requestID: UUID
    let goalID: UUID
    let expectedRevision: Int64
    let targetMinorUnits: Int64
    let currencyCode: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionMinorUnits: Int64?
    let items: [StoredItem]
    let budgetImportConfirmed: Bool
    let createdAt: Date
    var state: State
    var responseRevision: Int64?

    init(request: SavingPlanBudgetV2Request, ownerID: UUID,
         createdAt: Date = .now) throws {
        guard request.expectedOwnerID == ownerID,
              let target = PipoGoalCurrency.minorUnits(
                request.targetAmount, code: request.currencyCode),
              target > 0, request.targetDate.count <= 40,
              createdAt.timeIntervalSince1970.isFinite
        else { throw SavingPlanBudgetV2JournalError.invalidJournal }
        self.ownerID = ownerID
        requestID = request.requestID
        goalID = request.goalID
        expectedRevision = request.expectedRevision
        targetMinorUnits = target
        currencyCode = request.currencyCode
        targetDate = request.targetDate
        rhythm = request.rhythm
        preferredSavingDay = request.preferredSavingDay
        plannedContributionMinorUnits = request.plannedContributionOverride.flatMap {
            PipoGoalCurrency.minorUnits($0, code: request.currencyCode)
        }
        items = try request.items.map { item in
            guard let minor = PipoGoalCurrency.minorUnits(
                item.amount, code: request.currencyCode), minor > 0
            else { throw SavingPlanBudgetV2JournalError.invalidJournal }
            return StoredItem(id: item.id, title: item.title,
                              minorUnits: minor, isCompleted: item.isCompleted)
        }
        budgetImportConfirmed = request.budgetImportConfirmed
        self.createdAt = createdAt
        state = .staged
        responseRevision = nil
    }

    /// All JSON is UNTRUSTED on relaunch. Reconstruct the canonical V2 RPC
    /// request rather than trusting decoded item totals/UUIDs/currency.
    func checkedRequest(for expectedOwnerID: UUID) throws
        -> SavingPlanBudgetV2Request {
        guard ownerID == expectedOwnerID,
              let date = ISO8601DateFormatter().date(from: targetDate),
              createdAt.timeIntervalSince1970.isFinite
        else { throw SavingPlanBudgetV2JournalError.invalidJournal }
        do {
            let budget = try items.map {
                try SavingPlanBudgetV2Item(
                    id: $0.id, title: $0.title, minorUnits: $0.minorUnits,
                    currencyCode: currencyCode, isCompleted: $0.isCompleted
                )
            }
            let reconstructed = try SavingPlanBudgetV2Request(
                requestID: requestID, goalID: goalID,
                expectedRevision: expectedRevision,
                ownerID: expectedOwnerID, currencyCode: currencyCode,
                targetMinorUnits: targetMinorUnits, targetDate: date,
                rhythm: rhythm, preferredSavingDay: preferredSavingDay,
                plannedContributionMinorUnits: plannedContributionMinorUnits,
                items: budget,
                cloudBudgetNeedsReview: budgetImportConfirmed,
                userReviewedBudget: budgetImportConfirmed
            )
            guard reconstructed.targetDate == targetDate,
                  reconstructed.items == budget,
                  reconstructed.budgetImportConfirmed == budgetImportConfirmed
            else { throw SavingPlanBudgetV2JournalError.invalidJournal }
            switch state {
            case .staged:
                guard responseRevision == nil else {
                    throw SavingPlanBudgetV2JournalError.invalidJournal
                }
            case .acknowledged, .verified:
                guard responseRevision == expectedRevision + 1 else {
                    throw SavingPlanBudgetV2JournalError.invalidJournal
                }
            case .conflicted, .discarded:
                guard let responseRevision,
                      responseRevision >= 0,
                      responseRevision != expectedRevision else {
                    throw SavingPlanBudgetV2JournalError.invalidJournal
                }
            }
            return reconstructed
        } catch {
            throw SavingPlanBudgetV2JournalError.invalidJournal
        }
    }
}

/// No production call site. No automatic retry/rebase, no clearing of a
/// verified V2 intent before separately reviewed SwiftData reconciliation.
@MainActor
final class SavingPlanBudgetV2IntentJournal {
    private let directory: URL
    private let files: FileManager
    private let maximumEntries = 100 // no silent eviction/compaction

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        files = fileManager
    }

    static func inApplicationSupport() throws -> SavingPlanBudgetV2IntentJournal {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return SavingPlanBudgetV2IntentJournal(
            directory: root.appendingPathComponent(
                "PipoPendingBudgetCASV2", isDirectory: true
            )
        )
    }

    func all(for ownerID: UUID) throws -> [PendingSavingPlanBudgetV2Intent] {
        let url = fileURL(for: ownerID)
        guard files.fileExists(atPath: url.path) else { return [] }
        let entries: [PendingSavingPlanBudgetV2Intent]
        do {
            entries = try JSONDecoder().decode(
                [PendingSavingPlanBudgetV2Intent].self, from: Data(contentsOf: url)
            )
        } catch {
            throw SavingPlanBudgetV2JournalError.invalidJournal
        }
        guard entries.count <= maximumEntries else {
            throw SavingPlanBudgetV2JournalError.tooManyIntents
        }
        var ids = Set<UUID>(), activeGoals = Set<UUID>()
        for entry in entries {
            guard ids.insert(entry.requestID).inserted else {
                throw SavingPlanBudgetV2JournalError.invalidJournal
            }
            if entry.state != .discarded {
                guard activeGoals.insert(entry.goalID).inserted else {
                    throw SavingPlanBudgetV2JournalError.invalidJournal
                }
            }
            _ = try entry.checkedRequest(for: ownerID)
        }
        return entries
    }

    func pending(for ownerID: UUID) throws -> [PendingSavingPlanBudgetV2Intent] {
        try all(for: ownerID).filter { $0.state != .discarded }
    }

    /// Staging must precede network I/O; an exact retry keeps the UUID and
    /// immutable budget. A different payload with the same UUID fails.
    @discardableResult
    func stage(_ request: SavingPlanBudgetV2Request, ownerID: UUID) throws
        -> PendingSavingPlanBudgetV2Intent {
        guard request.expectedOwnerID == ownerID else {
            throw SavingPlanBudgetV2JournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        if let previous = entries.first(where: { $0.requestID == request.requestID }) {
            guard try previous.checkedRequest(for: ownerID) == request else {
                throw SavingPlanBudgetV2JournalError.idempotencyConflict
            }
            return previous
        }
        guard !entries.contains(where: {
            $0.goalID == request.goalID && $0.state != .discarded
        }) else { throw SavingPlanBudgetV2JournalError.goalAlreadyPending }
        guard entries.count < maximumEntries else {
            throw SavingPlanBudgetV2JournalError.tooManyIntents
        }
        let pending = try PendingSavingPlanBudgetV2Intent(
            request: request, ownerID: ownerID
        )
        entries.append(pending)
        try persist(entries, for: ownerID)
        return pending
    }

    /// Caller must validate Auth before AND after the awaited RPC, and pass
    /// only the exact decoded response from the authenticated server.
    func recordVerifiedResponse(
        _ response: SavingPlanBudgetV2WireResponse,
        requestID: UUID, ownerID: UUID, authenticatedOwnerID: UUID
    ) throws {
        guard ownerID == authenticatedOwnerID else {
            throw SavingPlanBudgetV2JournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        guard let i = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanBudgetV2JournalError.unknownIntent }
        let request = try entries[i].checkedRequest(for: ownerID)
        let outcome = try SavingPlanBudgetV2ReceiptValidator.verify(
            response, for: request
        )
        let next: PendingSavingPlanBudgetV2Intent.State
        let revision: Int64
        switch outcome {
        case .applied(_, let accepted):
            next = .acknowledged
            revision = accepted
        case .conflict(let current):
            next = .conflicted
            revision = current
        }
        if entries[i].state != .staged {
            let isExactRepeat = entries[i].state == next
                || (entries[i].state == .verified && next == .acknowledged)
            guard isExactRepeat,
                  entries[i].responseRevision == revision
            else { throw SavingPlanBudgetV2JournalError.invalidTransition }
            return
        }
        entries[i].state = next
        entries[i].responseRevision = revision
        try persist(entries, for: ownerID)
    }

    /// Never mark a receipt completed on response alone. This stage still
    /// does NOT change any SwiftData, savings, XP, achievements or local items.
    func recordAuthenticatedCurrentReadback(
        _ snapshot: SavingPlanBudgetV2CloudSnapshot,
        requestID: UUID, ownerID: UUID, authenticatedOwnerID: UUID
    ) throws {
        guard ownerID == authenticatedOwnerID else {
            throw SavingPlanBudgetV2JournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        guard let i = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanBudgetV2JournalError.unknownIntent }
        guard entries[i].state == .acknowledged || entries[i].state == .verified
        else { throw SavingPlanBudgetV2JournalError.invalidTransition }
        let request = try entries[i].checkedRequest(for: ownerID)
        guard SavingPlanBudgetV2SnapshotVerifier.matchesCurrent(
            snapshot, request: request, authenticatedOwnerID: authenticatedOwnerID
        ) else { throw SavingPlanBudgetV2JournalError.unverifiedReadback }
        if entries[i].state == .verified { return }
        entries[i].state = .verified
        try persist(entries, for: ownerID)
    }

    /// User chooses to DISCARD after a stale conflict; keep an immutable
    /// tombstone to prevent accidental UUID reuse during later restarts.
    func discardConflictedAfterUserDecision(
        requestID: UUID, ownerID: UUID, userConfirmedDiscard: Bool
    ) throws {
        guard userConfirmedDiscard else {
            throw SavingPlanBudgetV2JournalError.userDecisionRequired
        }
        var entries = try all(for: ownerID)
        guard let i = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanBudgetV2JournalError.unknownIntent }
        guard entries[i].state == .conflicted else {
            throw SavingPlanBudgetV2JournalError.invalidTransition
        }
        entries[i].state = .discarded
        try persist(entries, for: ownerID)
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directory.appendingPathComponent(
            ownerID.uuidString.lowercased() + ".json", isDirectory: false
        )
    }

    private func persist(
        _ entries: [PendingSavingPlanBudgetV2Intent], for ownerID: UUID
    ) throws {
        try files.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(entries)
        #if os(iOS)
        try data.write(
            to: fileURL(for: ownerID),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        #else
        try data.write(to: fileURL(for: ownerID), options: [.atomic])
        #endif
    }
}

// MARK: - #80: Dormant insert-only goal and authoritative readback contract
//
// This is an unconnected contract, NOT a network operation. The live app
// continues its old goal UPSERT until the signed-client compatibility gate.
// Never treat INSERT conflict/timeout as success without a verified SELECT.

enum SavingGoalCreateContractError: Error, Equatable {
    case invalidGoal
    case invalidAmount
    case invalidSchedule
    case accountChanged
    case missingOrInvisible
    case mismatchedRemoteGoal
    case remotelyRevised
}

/// INSERT-only payload: stable UUID and exact goal amounts. user_id is
/// intentionally omitted so PostgreSQL defaults it to auth.uid() under RLS.
/// The expected owner exists only in local verification, not the wire JSON.
struct SavingGoalCreateOnlyRequest: Encodable, Equatable, Sendable {
    let goalID: UUID
    let expectedOwnerID: UUID
    let title: String
    let category: String
    let customCategory: String?
    let targetAmount: Decimal
    let currencyCode: String
    let startDate: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?

    init(
        goalID: UUID, ownerID: UUID, title: String, category: String,
        customCategory: String?, targetMinorUnits: Int64,
        currencyCode: String, startDate: Date, targetDate: Date,
        rhythm: String, preferredSavingDay: Int?,
        plannedContributionMinorUnits: Int64?
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCustom = customCategory?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedTitle.isEmpty && normalizedTitle.count <= 120,
              ["gadget", "trip", "gift", "debt", "automotive", "house", "other"]
                .contains(category),
              normalizedCustom == nil || (normalizedCustom!.count > 0
                && normalizedCustom!.count <= 80)
        else { throw SavingGoalCreateContractError.invalidGoal }

        guard currencyCode == currencyCode.uppercased(),
              PipoGoalCurrency.isSupported(currencyCode),
              targetMinorUnits > 0,
              PipoGoalCurrency.minorUnits(
                PipoGoalCurrency.decimal(targetMinorUnits, code: currencyCode),
                code: currencyCode
              ) == targetMinorUnits
        else { throw SavingGoalCreateContractError.invalidAmount }

        var override: Decimal?
        if let plannedContributionMinorUnits {
            guard plannedContributionMinorUnits > 0,
                  PipoGoalCurrency.minorUnits(
                    PipoGoalCurrency.decimal(
                        plannedContributionMinorUnits, code: currencyCode
                    ), code: currencyCode
                  ) == plannedContributionMinorUnits
            else { throw SavingGoalCreateContractError.invalidAmount }
            override = PipoGoalCurrency.decimal(
                plannedContributionMinorUnits, code: currencyCode
            )
        }
        guard startDate.timeIntervalSince1970.isFinite,
              targetDate.timeIntervalSince1970.isFinite,
              targetDate >= startDate,
              ["daily", "weekly", "biWeekly", "monthly", "flexible"].contains(rhythm),
              preferredSavingDay == nil || (1...31).contains(preferredSavingDay!),
              (rhythm != "daily" && rhythm != "flexible"
                || preferredSavingDay == nil),
              (rhythm != "weekly" && rhythm != "biWeekly"
                || preferredSavingDay == nil || preferredSavingDay! <= 7),
              rhythm != "flexible" || override == nil
        else { throw SavingGoalCreateContractError.invalidSchedule }

        self.goalID = goalID
        expectedOwnerID = ownerID
        self.title = normalizedTitle
        self.category = category
        self.customCategory = normalizedCustom
        targetAmount = PipoGoalCurrency.decimal(
            targetMinorUnits, code: currencyCode
        )
        self.currencyCode = currencyCode
        let timestamp = ISO8601DateFormatter()
        self.startDate = timestamp.string(from: startDate)
        self.targetDate = timestamp.string(from: targetDate)
        self.rhythm = rhythm
        self.preferredSavingDay = preferredSavingDay
        plannedContributionOverride = override
    }

    enum CodingKeys: String, CodingKey {
        case title, category, rhythm
        case goalID = "id"
        case customCategory = "custom_category"
        case targetAmount = "target_amount"
        case currencyCode = "currency_code"
        case startDate = "start_date"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(goalID, forKey: .goalID)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encode(customCategory, forKey: .customCategory)
        try c.encode(targetAmount, forKey: .targetAmount)
        try c.encode(currencyCode, forKey: .currencyCode)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(targetDate, forKey: .targetDate)
        try c.encode(rhythm, forKey: .rhythm)
        try c.encode(preferredSavingDay, forKey: .preferredSavingDay)
        try c.encode(plannedContributionOverride, forKey: .plannedContributionOverride)
    }
}

/// A *fresh* SELECT from the RLS-filtered goal table. This DTO is not
/// itself proof the query was authenticated; verify the session before and
/// after fetching and pass only rows from that confirmed owner-scoped read.
struct SavingGoalAuthoritativeCloudRow: Decodable, Sendable {
    let goalID: UUID
    let ownerID: UUID
    let title: String
    let category: String
    let customCategory: String?
    let targetAmount: Decimal
    let currencyCode: String
    let startDate: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionOverride: Decimal?
    let planRevision: Int64

    enum CodingKeys: String, CodingKey {
        case title, category, rhythm
        case goalID = "id"
        case ownerID = "user_id"
        case customCategory = "custom_category"
        case targetAmount = "target_amount"
        case currencyCode = "currency_code"
        case startDate = "start_date"
        case targetDate = "target_date"
        case preferredSavingDay = "preferred_saving_day"
        case plannedContributionOverride = "planned_contribution_override"
        case planRevision = "plan_revision"
    }
}

enum SavingGoalCreateReadbackVerifier {
    private static func parseInstant(_ value: String) -> Date? {
        let seconds = ISO8601DateFormatter()
        if let instant = seconds.date(from: value) { return instant }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    /// Do NOT retry INSERT or mark the goal cloud-saved when readback is
    /// nil, foreign, changed, malformed, or revision > 0. In particular,
    /// a duplicate-key 409 is not evidence that the payload is identical.
    static func verify(
        _ row: SavingGoalAuthoritativeCloudRow?,
        for request: SavingGoalCreateOnlyRequest,
        authenticatedOwnerID: UUID
    ) throws {
        guard authenticatedOwnerID == request.expectedOwnerID else {
            throw SavingGoalCreateContractError.accountChanged
        }
        guard let row else {
            throw SavingGoalCreateContractError.missingOrInvisible
        }
        guard row.ownerID == authenticatedOwnerID,
              row.goalID == request.goalID
        else { throw SavingGoalCreateContractError.mismatchedRemoteGoal }
        guard row.planRevision == 0 else {
            throw SavingGoalCreateContractError.remotelyRevised
        }
        guard row.title == request.title,
              row.category == request.category,
              row.customCategory == request.customCategory,
              row.targetAmount == request.targetAmount,
              row.currencyCode == request.currencyCode,
              row.rhythm == request.rhythm,
              row.preferredSavingDay == request.preferredSavingDay,
              row.plannedContributionOverride == request.plannedContributionOverride,
              let start = parseInstant(row.startDate),
              let target = parseInstant(row.targetDate),
              let expectedStart = parseInstant(request.startDate),
              let expectedTarget = parseInstant(request.targetDate),
              start == expectedStart, target == expectedTarget
        else { throw SavingGoalCreateContractError.mismatchedRemoteGoal }
    }
}

// MARK: - #80: Durable first-goal create journal (inactive, NO network)
//
// Separate from the pending *plan-edit* journal. A goal's UUID itself is
// the stable INSERT idempotency key, including across timeout and relaunch.
// No automatic retries, live calls, SwiftData mutation, XP, or money movement.

enum SavingGoalCreateJournalError: Error, Equatable {
    case invalidJournal
    case idempotencyConflict
    case tooManyPendingGoals
    case unknownGoal
    case accountChanged
    case untrustedReadback
    case invalidTransition
    case userDecisionRequired
    case localNotReady
}

struct PendingSavingGoalCreateIntent: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case staged       // Persisted but no INSERT has been attempted.
        case attempted    // INSERT may have committed; MUST read before retry.
        case verified     // Exact owner/goal/revision-zero readback; local merge pending.
        case conflicted   // Owned goal exists but differs; user decision required.
        case reconciled   // Persisted local goal verified; durable terminal receipt.
    }

    let ownerID: UUID
    let goalID: UUID
    let title: String
    let category: String
    let customCategory: String?
    let targetMinorUnits: Int64
    let currencyCode: String
    let startDate: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionMinorUnits: Int64?
    let createdAt: Date
    var state: State
    var observedRevision: Int64?

    init(request: SavingGoalCreateOnlyRequest, createdAt: Date = .now) throws {
        guard let amount = PipoGoalCurrency.minorUnits(
                request.targetAmount, code: request.currencyCode),
              createdAt.timeIntervalSince1970.isFinite,
              (request.plannedContributionOverride == nil ||
               PipoGoalCurrency.minorUnits(
                 request.plannedContributionOverride!, code: request.currencyCode) != nil)
        else { throw SavingGoalCreateJournalError.invalidJournal }

        ownerID = request.expectedOwnerID
        goalID = request.goalID
        title = request.title
        category = request.category
        customCategory = request.customCategory
        targetMinorUnits = amount
        currencyCode = request.currencyCode
        startDate = request.startDate
        targetDate = request.targetDate
        rhythm = request.rhythm
        preferredSavingDay = request.preferredSavingDay
        plannedContributionMinorUnits = request.plannedContributionOverride.flatMap {
            PipoGoalCurrency.minorUnits($0, code: request.currencyCode)
        }
        self.createdAt = createdAt
        state = .staged
        observedRevision = nil
    }

    /// An on-disk JSON file is untrusted even when named after this user.
    /// Reconstruct the canonical request and check every immutable field.
    func checkedRequest(for ownerID: UUID) throws -> SavingGoalCreateOnlyRequest {
        guard self.ownerID == ownerID,
              createdAt.timeIntervalSince1970.isFinite,
              startDate.count <= 40, targetDate.count <= 40,
              let start = ISO8601DateFormatter().date(from: startDate),
              let target = ISO8601DateFormatter().date(from: targetDate)
        else { throw SavingGoalCreateJournalError.invalidJournal }
        let canonical: SavingGoalCreateOnlyRequest
        do {
            canonical = try SavingGoalCreateOnlyRequest(
                goalID: goalID, ownerID: ownerID,
                title: title, category: category, customCategory: customCategory,
                targetMinorUnits: targetMinorUnits, currencyCode: currencyCode,
                startDate: start, targetDate: target, rhythm: rhythm,
                preferredSavingDay: preferredSavingDay,
                plannedContributionMinorUnits: plannedContributionMinorUnits
            )
        } catch {
            throw SavingGoalCreateJournalError.invalidJournal
        }
        guard canonical.title == title,
              canonical.customCategory == customCategory,
              canonical.startDate == startDate, canonical.targetDate == targetDate
        else { throw SavingGoalCreateJournalError.invalidJournal }
        switch state {
        case .staged, .attempted:
            guard observedRevision == nil else {
                throw SavingGoalCreateJournalError.invalidJournal
            }
        case .verified, .reconciled:
            guard observedRevision == 0 else {
                throw SavingGoalCreateJournalError.invalidJournal
            }
        case .conflicted:
            guard let observedRevision, observedRevision >= 0 else {
                throw SavingGoalCreateJournalError.invalidJournal
            }
        }
        return canonical
    }
}

/// The journal itself NEVER treats an INSERT success, HTTP 409 or timeout as
/// a verified create. Only a FRESH, session-checked, owner-filtered SELECT
/// may be passed to recordReadback. This trust boundary is caller-enforced.
@MainActor
final class SavingGoalCreateIntentJournal {
    private let directory: URL
    private let files: FileManager
    private let maximumEntries = 100

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.files = fileManager
    }

    static func inApplicationSupport() throws -> SavingGoalCreateIntentJournal {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return SavingGoalCreateIntentJournal(
            directory: root.appendingPathComponent(
                "PipoPendingGoalCreates", isDirectory: true
            )
        )
    }

    func all(for ownerID: UUID) throws -> [PendingSavingGoalCreateIntent] {
        let path = fileURL(for: ownerID)
        guard files.fileExists(atPath: path.path) else { return [] }
        let entries: [PendingSavingGoalCreateIntent]
        do {
            entries = try JSONDecoder().decode(
                [PendingSavingGoalCreateIntent].self,
                from: Data(contentsOf: path)
            )
        } catch {
            throw SavingGoalCreateJournalError.invalidJournal
        }
        guard entries.count <= maximumEntries else {
            throw SavingGoalCreateJournalError.tooManyPendingGoals
        }
        var ids = Set<UUID>()
        for entry in entries {
            guard ids.insert(entry.goalID).inserted else {
                throw SavingGoalCreateJournalError.invalidJournal
            }
            _ = try entry.checkedRequest(for: ownerID)
        }
        return entries
    }

    /// Only unresolved entries are shown as pending; reconciled entries
    /// remain as durable receipts so an app relaunch cannot re-create a goal.
    func pending(for ownerID: UUID) throws -> [PendingSavingGoalCreateIntent] {
        try all(for: ownerID).filter { $0.state != .reconciled }
    }

    /// Persist BEFORE attempting a future authenticated INSERT. Never
    /// regenerate the goal UUID on relaunch or after an ambiguous timeout.
    @discardableResult
    func stage(_ request: SavingGoalCreateOnlyRequest, ownerID: UUID) throws
        -> PendingSavingGoalCreateIntent {
        guard request.expectedOwnerID == ownerID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        if let earlier = entries.first(where: { $0.goalID == request.goalID }) {
            guard try earlier.checkedRequest(for: ownerID) == request else {
                throw SavingGoalCreateJournalError.idempotencyConflict
            }
            return earlier
        }
        guard entries.count < maximumEntries else {
            throw SavingGoalCreateJournalError.tooManyPendingGoals
        }
        let entry = try PendingSavingGoalCreateIntent(request: request)
        entries.append(entry)
        try persist(entries, for: ownerID)
        return entry
    }

    /// Persist BEFORE the first network INSERT. On timeout or crash, read back
    /// the original UUID instead of automatically issuing another INSERT.
    @discardableResult
    func markInsertAttempted(goalID: UUID, ownerID: UUID)
        throws -> SavingGoalCreateOnlyRequest {
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: { $0.goalID == goalID }) else {
            throw SavingGoalCreateJournalError.unknownGoal
        }
        guard entries[index].state == .staged else {
            throw SavingGoalCreateJournalError.invalidTransition
        }
        let request = try entries[index].checkedRequest(for: ownerID)
        entries[index].state = .attempted
        try persist(entries, for: ownerID)
        return request
    }

    /// Nil/unauthorized readback never changes state. An owned mismatching
    /// row becomes a CONFLICT rather than a new INSERT or an overwrite.
    /// No state transition performs a network request or changes SwiftData.
    @discardableResult
    func recordReadback(
        _ row: SavingGoalAuthoritativeCloudRow?,
        goalID: UUID,
        ownerID: UUID,
        authenticatedOwnerID: UUID
    ) throws -> PendingSavingGoalCreateIntent.State {
        guard authenticatedOwnerID == ownerID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        guard let i = entries.firstIndex(where: { $0.goalID == goalID }) else {
            throw SavingGoalCreateJournalError.unknownGoal
        }
        let request = try entries[i].checkedRequest(for: ownerID)

        // Missing row means unknown/invisible, NOT a safe reason to create
        // another UUID or drop the pending entry.
        guard let row else {
            throw SavingGoalCreateContractError.missingOrInvisible
        }
        guard row.ownerID == ownerID, row.goalID == goalID,
              row.planRevision >= 0 else {
            throw SavingGoalCreateJournalError.untrustedReadback
        }
        let next: PendingSavingGoalCreateIntent.State
        do {
            try SavingGoalCreateReadbackVerifier.verify(
                row, for: request, authenticatedOwnerID: authenticatedOwnerID
            )
            next = .verified
        } catch SavingGoalCreateContractError.remotelyRevised {
            next = .conflicted
        } catch SavingGoalCreateContractError.mismatchedRemoteGoal {
            next = .conflicted
        }
        let observed = row.planRevision
        if entries[i].state == .reconciled {
            guard next == .verified, observed == 0 else {
                throw SavingGoalCreateJournalError.invalidTransition
            }
            return .reconciled
        }
        if entries[i].state != .staged && entries[i].state != .attempted {
            guard entries[i].state == next,
                  entries[i].observedRevision == observed else {
                throw SavingGoalCreateJournalError.invalidTransition
            }
            return next
        }
        entries[i].state = next
        entries[i].observedRevision = observed
        try persist(entries, for: ownerID)
        return next
    }

    /// This method is not automatically called from app lifecycle. A future
    /// staging-only SwiftData adapter must first read a FRESH persisted goal
    /// from a separate ModelContext and prove that local records/budget/XP
    /// have not been modified. This writes ONLY a durable terminal receipt
    /// into the create journal: it never edits SwiftData, history, or XP.
    @discardableResult
    func markLocalCommitVerified(
        goalID: UUID, ownerID: UUID, authenticatedOwnerID: UUID,
        local: SavingGoalCreateLocalSnapshot
    ) throws -> PendingSavingGoalCreateIntent.State {
        guard ownerID == authenticatedOwnerID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: { $0.goalID == goalID }) else {
            throw SavingGoalCreateJournalError.unknownGoal
        }
        let pending = entries[index]
        let expected = try pending.checkedRequest(for: ownerID)
        guard expected == local.request else {
            throw SavingGoalCreateJournalError.localNotReady
        }
        // Repeat after an interrupted app cleanup is idempotent and never
        // creates a second goal or changes the already recorded history.
        if pending.state == .reconciled {
            guard pending.observedRevision == 0,
                  local.ownerID == ownerID, local.pendingSavingEventCount == 0,
                  !local.hasLocalOnlyBudgetItems,
                  !local.hasUnresolvedPlanChanges else {
                throw SavingGoalCreateJournalError.localNotReady
            }
            return .reconciled
        }
        guard try SavingGoalCreateLocalReconciler.assess(
            pending: pending, local: local,
            authenticatedOwnerID: authenticatedOwnerID
        ) == .eligibleForExplicitReconciliation else {
            throw SavingGoalCreateJournalError.localNotReady
        }
        entries[index].state = .reconciled
        // Atomic write is the commit. Crash before => verified can retry;
        // crash after => reconciled survives and is hidden from pending().
        try persist(entries, for: ownerID)
        return .reconciled
    }

    func discardConflictedAfterUserDecision(
        goalID: UUID, ownerID: UUID, userConfirmedDiscard: Bool
    ) throws {
        guard userConfirmedDiscard else {
            throw SavingGoalCreateJournalError.userDecisionRequired
        }
        var entries = try all(for: ownerID)
        guard let i = entries.firstIndex(where: { $0.goalID == goalID }) else {
            throw SavingGoalCreateJournalError.unknownGoal
        }
        guard entries[i].state == .conflicted else {
            throw SavingGoalCreateJournalError.invalidTransition
        }
        entries.remove(at: i)
        try persist(entries, for: ownerID)
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directory.appendingPathComponent(
            ownerID.uuidString.lowercased() + ".json", isDirectory: false
        )
    }

    private func persist(
        _ entries: [PendingSavingGoalCreateIntent], for ownerID: UUID
    ) throws {
        try files.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(entries)
        #if os(iOS)
        try data.write(
            to: fileURL(for: ownerID),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        #else
        // Ephemeral, isolated Linux Swift harness only.
        try data.write(to: fileURL(for: ownerID), options: [.atomic])
        #endif
    }
}

// MARK: - #80: Pure local reconcile decision (NO SwiftData writes)
//
// A verified CREATE does not certify that saving events, XP, budget subitems
// and device-local edits have been safely reconciled. This checker returns
// *advice only*, never removes a journal row or rewrites any financial data.

struct SavingGoalCreateLocalSnapshot: Sendable {
    let ownerID: UUID
    let request: SavingGoalCreateOnlyRequest
    let pendingSavingEventCount: Int
    let hasLocalOnlyBudgetItems: Bool
    let hasUnresolvedPlanChanges: Bool
}

enum SavingGoalCreateReconcileDecision: Equatable, Sendable {
    case holdForAuthenticatedReadback
    case holdForLocalConflict
    case goalVerifiedSavingEntriesPending
    case goalVerifiedBudgetSyncPending
    case eligibleForExplicitReconciliation
}

enum SavingGoalCreateLocalReconciler {
    static func assess(
        pending: PendingSavingGoalCreateIntent,
        local: SavingGoalCreateLocalSnapshot,
        authenticatedOwnerID: UUID
    ) throws -> SavingGoalCreateReconcileDecision {
        guard authenticatedOwnerID == pending.ownerID,
              local.ownerID == authenticatedOwnerID,
              local.request.expectedOwnerID == authenticatedOwnerID
        else { throw SavingGoalCreateJournalError.accountChanged }
        guard local.pendingSavingEventCount >= 0 else {
            throw SavingGoalCreateJournalError.invalidJournal
        }
        // A conflict cannot be safely resolved by comparing only a saved
        // stale snapshot. Require a fresh server fetch + explicit user input.
        guard pending.state == .verified, pending.observedRevision == 0 else {
            return .holdForAuthenticatedReadback
        }
        let expected = try pending.checkedRequest(for: authenticatedOwnerID)
        guard expected == local.request,
              !local.hasUnresolvedPlanChanges
        else { return .holdForLocalConflict }

        // The user's new goal can be known on cloud while saving events
        // remain offline. Do not grant XP or copy balances during recovery.
        if local.pendingSavingEventCount > 0 {
            return .goalVerifiedSavingEntriesPending
        }
        if local.hasLocalOnlyBudgetItems {
            return .goalVerifiedBudgetSyncPending
        }
        // This is a planning decision, NOT permission to automatically
        // remove a verified journal. A separately reviewed app integration
        // must commit local reconciliation and its receipt first.
        return .eligibleForExplicitReconciliation
    }
}

// MARK: - #80: Durable local plan-edit intent (inactive, NO network send)
//
// Stored separately per authenticated owner using an atomic write, without a
// SwiftData schema migration. This is a delivery journal, not a second source
// of financial truth. A staged/acknowledged entry NEVER updates goal totals,
// XP, badges, currency or the current SwiftData plan. All transitions are
// called explicitly; there is no automatic retry or background task.

enum SavingPlanCASJournalError: Error, Equatable {
    case invalidJournal
    case idempotencyConflict
    case goalAlreadyPending
    case tooManyIntents
    case unknownIntent
    case invalidTransition
    case unverifiedReadback
    case userDecisionRequired
}

struct PendingSavingPlanCASIntent: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case staged       // Not confirmed: timeout and offline remain here.
        case acknowledged // Exact RPC receipt verified, readback still needed.
        case conflicted   // Latest server revision differs; user must decide.
    }

    let ownerID: UUID
    let requestID: UUID
    let goalID: UUID
    let expectedRevision: Int64
    let targetMinorUnits: Int64
    let currencyCode: String
    let targetDate: String
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionMinorUnits: Int64?
    let createdAt: Date
    var state: State
    var responseRevision: Int64?

    init(request: SavingPlanCASRequest, ownerID: UUID, createdAt: Date = .now) throws {
        guard let target = PipoGoalCurrency.minorUnits(
                request.targetAmount, code: request.currencyCode),
              request.targetDate.count <= 40,
              (request.plannedContributionOverride == nil ||
               PipoGoalCurrency.minorUnits(
                 request.plannedContributionOverride!, code: request.currencyCode) != nil)
        else { throw SavingPlanCASJournalError.invalidJournal }
        self.ownerID = ownerID
        requestID = request.requestID
        goalID = request.goalID
        expectedRevision = request.expectedRevision
        targetMinorUnits = target
        currencyCode = request.currencyCode
        targetDate = request.targetDate
        rhythm = request.rhythm
        preferredSavingDay = request.preferredSavingDay
        plannedContributionMinorUnits = request.plannedContributionOverride.flatMap {
            PipoGoalCurrency.minorUnits($0, code: request.currencyCode)
        }
        self.createdAt = createdAt
        state = .staged
        responseRevision = nil
    }

    /// Treat every on-disk entry as untrusted after relaunch. A malformed
    /// payload fails the whole journal closed, never silently drops edits.
    func checkedRequest(for ownerID: UUID) throws -> SavingPlanCASRequest {
        guard self.ownerID == ownerID,
              expectedRevision >= 0 && expectedRevision < Int64.max,
              let date = ISO8601DateFormatter().date(from: targetDate),
              createdAt.timeIntervalSince1970.isFinite
        else { throw SavingPlanCASJournalError.invalidJournal }
        let canonical = try SavingPlanCASRequest(
            requestID: requestID, goalID: goalID, expectedRevision: expectedRevision,
            targetMinorUnits: targetMinorUnits, currencyCode: currencyCode,
            targetDate: date, rhythm: rhythm,
            preferredSavingDay: preferredSavingDay,
            plannedContributionMinorUnits: plannedContributionMinorUnits
        )
        guard canonical.targetDate == targetDate else {
            throw SavingPlanCASJournalError.invalidJournal
        }
        switch state {
        case .staged:
            guard responseRevision == nil else {
                throw SavingPlanCASJournalError.invalidJournal
            }
        case .acknowledged:
            guard responseRevision == expectedRevision + 1 else {
                throw SavingPlanCASJournalError.invalidJournal
            }
        case .conflicted:
            guard let responseRevision, responseRevision >= 0,
                  responseRevision != expectedRevision else {
                throw SavingPlanCASJournalError.invalidJournal
            }
        }
        return canonical
    }
}

/// Must be constructed ONLY from an authenticated, RLS-authorized server
/// current-goal fetch; this structure alone does not prove authorization.
struct SavingPlanCASGoalReadback: Equatable, Sendable {
    let ownerID: UUID
    let goalID: UUID
    let revision: Int64
    let targetMinorUnits: Int64
    let currencyCode: String
    let targetDate: Date
    let rhythm: String
    let preferredSavingDay: Int?
    let plannedContributionMinorUnits: Int64?
}

/// No caller automatically drains this queue. No app production action is
/// currently wired to stage, acknowledge, resolve, or finish an intent.
@MainActor
final class SavingPlanCASIntentJournal {
    private let directory: URL
    private let files: FileManager
    private let maximumEntries = 100

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        files = fileManager
    }

    static func inApplicationSupport() throws -> SavingPlanCASIntentJournal {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return SavingPlanCASIntentJournal(
            directory: root.appendingPathComponent(
                "PipoPendingPlanCAS", isDirectory: true
            )
        )
    }

    func all(for ownerID: UUID) throws -> [PendingSavingPlanCASIntent] {
        let url = fileURL(for: ownerID)
        guard files.fileExists(atPath: url.path) else { return [] }
        let entries: [PendingSavingPlanCASIntent]
        do {
            entries = try JSONDecoder().decode(
                [PendingSavingPlanCASIntent].self, from: Data(contentsOf: url)
            )
        } catch {
            throw SavingPlanCASJournalError.invalidJournal
        }
        guard entries.count <= maximumEntries else {
            throw SavingPlanCASJournalError.tooManyIntents
        }
        var ids = Set<UUID>(), goals = Set<UUID>()
        for entry in entries {
            guard ids.insert(entry.requestID).inserted,
                  goals.insert(entry.goalID).inserted
            else { throw SavingPlanCASJournalError.invalidJournal }
            do { _ = try entry.checkedRequest(for: ownerID) }
            catch { throw SavingPlanCASJournalError.invalidJournal }
        }
        return entries
    }

    /// Must run BEFORE any attempted RPC, with one stable UUID. Blocks a
    /// second unresolved edit to the same goal (including a conflict).
    @discardableResult
    func stage(_ request: SavingPlanCASRequest, ownerID: UUID) throws
        -> PendingSavingPlanCASIntent {
        var entries = try all(for: ownerID)
        if let previous = entries.first(where: { $0.requestID == request.requestID }) {
            guard try previous.checkedRequest(for: ownerID) == request else {
                throw SavingPlanCASJournalError.idempotencyConflict
            }
            return previous
        }
        guard !entries.contains(where: { $0.goalID == request.goalID }) else {
            throw SavingPlanCASJournalError.goalAlreadyPending
        }
        guard entries.count < maximumEntries else {
            throw SavingPlanCASJournalError.tooManyIntents
        }
        let intent = try PendingSavingPlanCASIntent(request: request, ownerID: ownerID)
        entries.append(intent)
        try persist(entries, for: ownerID)
        return intent
    }

    /// Accept no success or conflict merely from HTTP 200. The receipt
    /// validator compares exact goal/UUID/amount/date/currency/revision.
    func recordVerifiedResponse(
        _ response: SavingPlanCASWireResponse, requestID: UUID, ownerID: UUID
    ) throws {
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanCASJournalError.unknownIntent }
        let expected = try entries[index].checkedRequest(for: ownerID)
        let result = try SavingPlanCASReceiptValidator.verify(response, for: expected)
        let nextState: PendingSavingPlanCASIntent.State
        let revision: Int64
        switch result {
        case .applied(_, let accepted):
            nextState = .acknowledged
            revision = accepted
        case .conflict(let current):
            nextState = .conflicted
            revision = current
        }
        if entries[index].state != .staged {
            guard entries[index].state == nextState,
                  entries[index].responseRevision == revision
            else { throw SavingPlanCASJournalError.invalidTransition }
            return
        }
        entries[index].state = nextState
        entries[index].responseRevision = revision
        try persist(entries, for: ownerID)
    }

    /// Receipt alone is insufficient: a replayed receipt might refer to an
    /// older state. Only remove after a fresh, owner-scoped CURRENT server
    /// readback matches the entire original amendment and exact revision.
    func finishVerifiedCurrentReadback(
        requestID: UUID, ownerID: UUID, current: SavingPlanCASGoalReadback
    ) throws {
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanCASJournalError.unknownIntent }
        let item = entries[index]
        guard item.state == .acknowledged,
              item.ownerID == ownerID, current.ownerID == ownerID,
              current.goalID == item.goalID,
              current.revision == item.responseRevision,
              current.targetMinorUnits == item.targetMinorUnits,
              current.currencyCode == item.currencyCode,
              ISO8601DateFormatter().string(from: current.targetDate) == item.targetDate,
              current.rhythm == item.rhythm,
              current.preferredSavingDay == item.preferredSavingDay,
              current.plannedContributionMinorUnits == item.plannedContributionMinorUnits
        else { throw SavingPlanCASJournalError.unverifiedReadback }
        entries.remove(at: index)
        try persist(entries, for: ownerID)
    }

    /// No silent last-write-wins. A conflict stays until the user explicitly
    /// discards/rebases the draft in a future reviewed UI.
    func discardConflictedAfterUserDecision(
        requestID: UUID, ownerID: UUID, userConfirmedDiscard: Bool
    ) throws {
        guard userConfirmedDiscard else {
            throw SavingPlanCASJournalError.userDecisionRequired
        }
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: { $0.requestID == requestID })
        else { throw SavingPlanCASJournalError.unknownIntent }
        guard entries[index].state == .conflicted else {
            throw SavingPlanCASJournalError.invalidTransition
        }
        entries.remove(at: index)
        try persist(entries, for: ownerID)
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directory.appendingPathComponent(
            ownerID.uuidString.lowercased() + ".json", isDirectory: false
        )
    }

    private func persist(
        _ entries: [PendingSavingPlanCASIntent], for ownerID: UUID
    ) throws {
        try files.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let bytes = try JSONEncoder().encode(entries)
        #if os(iOS)
        // Protected while the device is locked; use a strong iOS data-
        // protection class rather than writing an unprotected JSON queue.
        try bytes.write(to: fileURL(for: ownerID),
                        options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        // Linux-only isolated contract harness, never an app delivery path.
        try bytes.write(to: fileURL(for: ownerID), options: [.atomic])
        #endif
    }
}

enum SavingMoneyOutRequestError: Error, Equatable {
    case invalidAmount
    case invalidNote
    case invalidPreference
    case mismatchedServerReceipt
}

/// Stable idempotency key must be created before the first send and reused
/// unchanged after a timeout or a relaunch. NEVER regenerate it on retry.
/// This does not move bank money; the server only records manual saving usage.
struct SavingMoneyOutRPCRequest: Codable, Sendable {
    let requestID: UUID
    let goalID: UUID
    let amount: Int
    let note: String?
    let preference: String

    init(requestID: UUID, goalID: UUID, amount: Int, note: String?,
         preference: String) throws {
        guard amount > 0, amount <= SavingsAmountSafety.maxExactWholeIDR else {
            throw SavingMoneyOutRequestError.invalidAmount
        }
        guard ["keep_date", "keep_amount"].contains(preference) else {
            throw SavingMoneyOutRequestError.invalidPreference
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed?.count ?? 0) <= 240 else {
            throw SavingMoneyOutRequestError.invalidNote
        }
        self.requestID = requestID
        self.goalID = goalID
        self.amount = amount
        self.note = trimmed?.isEmpty == true ? nil : trimmed
        self.preference = preference
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "p_id"
        case goalID = "p_goal_id"
        case amount = "p_amount"
        case note = "p_note"
        case preference = "p_preference"
    }
}

/// Crash-safe local delivery intent, never a declaration that money has moved.
/// A pending request remains pending after a network timeout and must be retried
/// with its original ID. Acknowledged requests remain until cloud readback.
struct PendingMoneyOutIntent: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case staged
        case acknowledged
    }

    let ownerID: UUID
    let request: SavingMoneyOutRPCRequest
    let createdAt: Date
    var state: State

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ownerID == rhs.ownerID &&
        lhs.request.requestID == rhs.request.requestID &&
        lhs.request.goalID == rhs.request.goalID &&
        lhs.request.amount == rhs.request.amount &&
        lhs.request.note == rhs.request.note &&
        lhs.request.preference == rhs.request.preference &&
        lhs.createdAt == rhs.createdAt && lhs.state == rhs.state
    }
}

enum MoneyOutJournalError: Error, Equatable {
    case idempotencyConflict
    case unknownIntent
    case notAcknowledged
    case unverifiedCloudReceipt
    case invalidJournal
    case tooManyPendingIntents
}

/// The application-support journal is separate from SwiftData migrations.
/// It deliberately does not auto-retry or modify balance; those operations
/// require the approved server rollout and explicit account/session guards.
/// MainActor serializes journal read/modify/write on the current device.
@MainActor
final class MoneyOutIntentJournal {
    private let directory: URL
    private let files: FileManager
    private let maximumEntries = 500

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.files = fileManager
    }

    static func inApplicationSupport() throws -> MoneyOutIntentJournal {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return MoneyOutIntentJournal(
            directory: root.appendingPathComponent(
                "PipoMoneyOutIntents", isDirectory: true
            )
        )
    }

    func all(for ownerID: UUID) throws -> [PendingMoneyOutIntent] {
        let path = fileURL(for: ownerID)
        guard files.fileExists(atPath: path.path) else { return [] }
        let data = try Data(contentsOf: path)
        let entries: [PendingMoneyOutIntent]
        do {
            entries = try JSONDecoder().decode(
                [PendingMoneyOutIntent].self, from: data
            )
        } catch {
            throw MoneyOutJournalError.invalidJournal
        }
        guard entries.count <= maximumEntries else {
            throw MoneyOutJournalError.tooManyPendingIntents
        }
        var ids = Set<UUID>()
        for entry in entries {
            guard entry.ownerID == ownerID,
                  ids.insert(entry.request.requestID).inserted,
                  let canonical = try? SavingMoneyOutRPCRequest(
                    requestID: entry.request.requestID,
                    goalID: entry.request.goalID,
                    amount: entry.request.amount,
                    note: entry.request.note,
                    preference: entry.request.preference
                  ),
                  canonical.note == entry.request.note
            else { throw MoneyOutJournalError.invalidJournal }
        }
        return entries
    }

    @discardableResult
    func stage(
        _ request: SavingMoneyOutRPCRequest,
        ownerID: UUID
    ) throws -> PendingMoneyOutIntent {
        var entries = try all(for: ownerID)
        if let existing = entries.first(where: {
            $0.request.requestID == request.requestID
        }) {
            guard existing.request.goalID == request.goalID,
                  existing.request.amount == request.amount,
                  existing.request.note == request.note,
                  existing.request.preference == request.preference
            else { throw MoneyOutJournalError.idempotencyConflict }
            return existing
        }
        guard entries.count < maximumEntries else {
            throw MoneyOutJournalError.tooManyPendingIntents
        }
        let entry = PendingMoneyOutIntent(
            ownerID: ownerID, request: request,
            createdAt: .now, state: .staged
        )
        entries.append(entry)
        try persist(entries, ownerID: ownerID)
        return entry
    }

    /// Call only after submitVerifiedMoneyOut has checked the actual receipt.
    func acknowledge(
        requestID: UUID, receipt: SavingMoneyOutRPCReceipt,
        ownerID: UUID
    ) throws {
        var entries = try all(for: ownerID)
        guard let index = entries.firstIndex(where: {
            $0.request.requestID == requestID
        }) else { throw MoneyOutJournalError.unknownIntent }
        try receipt.verify(request: entries[index].request, ownerID: ownerID)
        entries[index].state = .acknowledged
        try persist(entries, ownerID: ownerID)
    }

    /// Readback must include the exact server adjustment before the local
    /// delivery intent can be discarded. The returned snapshot is still
    /// read-only; local goal balances are NOT automatically overwritten.
    @discardableResult
    func finishVerifiedReadback(
        requestID: UUID,
        cloud: SavingLedgerCloudSnapshotEnvelope,
        ownerID: UUID
    ) throws -> SavingLedgerSnapshot {
        let entries = try all(for: ownerID)
        guard let entry = entries.first(where: {
            $0.request.requestID == requestID
        }) else { throw MoneyOutJournalError.unknownIntent }
        guard entry.state == .acknowledged else {
            throw MoneyOutJournalError.notAcknowledged
        }
        guard cloud.goalID == entry.request.goalID,
              cloud.userID == ownerID,
              cloud.adjustments.contains(where: {
                $0.id == requestID && $0.goalID == entry.request.goalID &&
                $0.userID == ownerID && $0.kind == "money_out" &&
                $0.amount.isFinite &&
                Int(exactly: $0.amount) == entry.request.amount
              })
        else { throw MoneyOutJournalError.unverifiedCloudReceipt }
        let snapshot = try SavingCloudLedgerReconciler.reconstruct(
            goalID: cloud.goalID, ownerID: ownerID,
            contributions: cloud.contributions, adjustments: cloud.adjustments
        )
        try persist(
            entries.filter { $0.request.requestID != requestID },
            ownerID: ownerID
        )
        return snapshot
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directory.appendingPathComponent(
            ownerID.uuidString.lowercased() + ".json", isDirectory: false
        )
    }

    private func persist(
        _ entries: [PendingMoneyOutIntent], ownerID: UUID
    ) throws {
        try files.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let payload = try JSONEncoder().encode(entries)
        try payload.write(
            to: fileURL(for: ownerID),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }
}

struct SavingMoneyOutRPCReceipt: Decodable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let kind: String
    let amount: Double
    let preference: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, amount, preference, note
        case goalID = "goal_id"
        case userID = "user_id"
    }

    func verify(request: SavingMoneyOutRPCRequest, ownerID: UUID) throws {
        guard id == request.requestID, goalID == request.goalID, userID == ownerID,
              kind == "money_out", amount.isFinite,
              amount <= Double(SavingsAmountSafety.maxExactWholeIDR),
              Int(exactly: amount) == request.amount,
              preference == request.preference,
              note == request.note
        else { throw SavingMoneyOutRequestError.mismatchedServerReceipt }
    }
}

/// A single PostgreSQL statement snapshot prevents torn cross-device reads.
/// The RPC enforces owner RLS; the client independently validates identity.
struct SavingLedgerCloudSnapshotEnvelope: Decodable, Sendable {
    let goalID: UUID
    let userID: UUID
    let contributions: [SavingLedgerCloudContribution]
    let adjustments: [SavingLedgerCloudAdjustment]

    enum CodingKeys: String, CodingKey {
        case goalID = "goal_id"
        case userID = "user_id"
        case contributions, adjustments
    }
}

enum SavingCloudRecoveryError: Error, Equatable {
    case invalidServerEntry
    case accountChanged
    case tooManyEntries
}

/// Strict, pure reconstruction of independently fetched cloud rows.
/// No local SwiftData changes occur until an explicit reconciliation policy
/// for unsynced contributions has been reviewed and approved.
enum SavingCloudLedgerReconciler {
    /// PostgreSQL timestamptz may include fractional seconds; accepting only
    /// a strict ISO8601 timestamp prevents locale-dependent recovery.
    private static func decodeTimestamp(_ source: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let timestamp = formatter.date(from: source) { return timestamp }
        formatter.formatOptions = [.withInternetDateTime]
        if let timestamp = formatter.date(from: source) { return timestamp }
        throw SavingCloudRecoveryError.invalidServerEntry
    }

    static func reconstruct(
        goalID: UUID, ownerID: UUID,
        contributions: [SavingLedgerCloudContribution],
        adjustments: [SavingLedgerCloudAdjustment]
    ) throws -> SavingLedgerSnapshot {
        guard contributions.count <= 10_000, adjustments.count <= 10_000 else {
            throw SavingCloudRecoveryError.tooManyEntries
        }
        let savings: [SavingTransaction] = try contributions.map { entry in
            guard entry.goalID == goalID, entry.userID == ownerID,
                  entry.amount.isFinite, let amount = Int(exactly: entry.amount),
                  amount > 0,
                  amount <= SavingsAmountSafety.maxExactWholeIDR,
                  entry.xpEarned >= 0
            else { throw SavingCloudRecoveryError.invalidServerEntry }
            return SavingTransaction(
                id: entry.id, goalId: entry.goalID, amount: Double(amount),
                xpEarned: entry.xpEarned, date: try decodeTimestamp(entry.date), userID: entry.userID
            )
        }
        let events: [SavingAdjustmentEvent] = try adjustments.map { entry in
            guard entry.goalID == goalID, entry.userID == ownerID,
                  let kind = SavingAdjustmentKind(rawValue: entry.kind),
                  entry.amount.isFinite, let amount = Int(exactly: entry.amount),
                  amount != 0,
                  amount >= -SavingsAmountSafety.maxExactWholeIDR,
                  amount <= SavingsAmountSafety.maxExactWholeIDR
            else { throw SavingCloudRecoveryError.invalidServerEntry }
            return SavingAdjustmentEvent(
                id: entry.id, goalID: entry.goalID, userID: entry.userID,
                kind: kind, amount: amount,
                correctsEventID: entry.correctsEventID, date: try decodeTimestamp(entry.createdAt)
            )
        }
        return try SavingLedgerSnapshot.reconstruct(
            goalID: goalID, ownerID: ownerID, savings: savings,
            adjustments: events
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

/// The server function must verify a live user session and derive the user ID
/// from Supabase Auth. A response alone does not represent local cleanup.
struct AccountDeletionResponse: Decodable, Sendable {
    let deleted: Bool
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case deleted
        case userID = "user_id"
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
    case deletionNotConfirmed
    case socialSignInUnavailable

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
        case .deletionNotConfirmed:
            "Pipo could not confirm account deletion. Your local data was not removed."
        case .socialSignInUnavailable:
            "Social sign-in is not available yet. Use your email address."
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
        guard AuthProviderAvailability.socialSignInEnabled else {
            throw SupabaseServiceError.socialSignInUnavailable
        }
        let session = try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: configuration.redirectURL
        )
        authStateManager.signIn(userID: session.user.id)
    }

    /// Never use a service-role key in the app. The backend's authenticated
    /// delete-account function chooses the user from the verified bearer token.
    func requestPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email, redirectTo: configuration.passwordRecoveryRedirectURL
        )
    }

    func updateRecoveredPassword(_ password: String) async throws {
        guard client.auth.currentUser != nil else {
            throw SupabaseServiceError.notAuthenticated
        }
        try await client.auth.update(user: UserAttributes(password: password))
    }

    func deleteCurrentAccount(accountID: UUID) async throws {
        guard client.auth.currentUser?.id == accountID else {
            throw SupabaseServiceError.notAuthenticated
        }
        // The expected UUID is only a fail-closed consistency check. The
        // server MUST derive deletion authority from the verified bearer JWT.
        let result: AccountDeletionResponse = try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(
                body: ["expected_user_id": accountID.uuidString.lowercased()]
            )
        )
        guard result.deleted, result.userID == accountID else {
            throw SupabaseServiceError.deletionNotConfirmed
        }
    }

    /// Auth user has been deleted server-side; sign out the cached SDK session
    /// best-effort even if Auth no longer recognizes the deleted identity.
    func discardDeletedSession(using authStateManager: AuthStateManager) async {
        try? await client.auth.signOut()
        authStateManager.signOut()
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
        // Historical contributions are immutable events. A retry with the
        // same UUID must NEVER update amount, goal, date or awarded XP in
        // the cloud, regardless of which device sent the retry.
        //
        // PostgREST ignore-duplicates is an atomic INSERT ... ON CONFLICT
        // DO NOTHING, preserving offline UUID idempotency. This is a client
        // guard only; server-side UPDATE/DELETE grants and conflict-aware
        // read reconciliation remain release blockers (#29/#16/#42).
        try await client
            .from("saving_transactions")
            .upsert(payloads, onConflict: "id", ignoreDuplicates: true)
            .execute()
    }

    /// Authenticated, idempotent RPC adapter for the proposed atomic server
    /// function. NOT connected to any production button until DB migration,
    /// crash-safe intent persistence and verified reconciliation are complete.
    func submitVerifiedMoneyOut(
        _ request: SavingMoneyOutRPCRequest, authenticatedUserID: UUID
    ) async throws -> SavingMoneyOutRPCReceipt {
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SupabaseServiceError.notAuthenticated
        }
        let receipt = try await performMoneyOutRPC(request)
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingCloudRecoveryError.accountChanged
        }
        try receipt.verify(request: request, ownerID: authenticatedUserID)
        return receipt
    }

    private nonisolated func performMoneyOutRPC(
        _ request: SavingMoneyOutRPCRequest
    ) async throws -> SavingMoneyOutRPCReceipt {
        try await client.rpc("record_money_out", params: request)
            .execute().value
    }

    /// Reads one RLS-authorized database snapshot instead of racing two
    /// independent requests. Never overwrites device-only unsynced entries.
    /// Unavailable until the proposed database RPC is deployed and tested.
    func fetchVerifiedSavingLedger(
        goalID: UUID,
        authenticatedUserID: UUID
    ) async throws -> SavingLedgerSnapshot {
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SupabaseServiceError.notAuthenticated
        }
        let cloud = try await fetchAtomicSavingLedgerSnapshot(goalID: goalID)
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingCloudRecoveryError.accountChanged
        }
        guard cloud.goalID == goalID, cloud.userID == authenticatedUserID else {
            throw SavingCloudRecoveryError.invalidServerEntry
        }
        return try SavingCloudLedgerReconciler.reconstruct(
            goalID: goalID, ownerID: authenticatedUserID,
            contributions: cloud.contributions, adjustments: cloud.adjustments
        )
    }

    private nonisolated func fetchAtomicSavingLedgerSnapshot(
        goalID: UUID
    ) async throws -> SavingLedgerCloudSnapshotEnvelope {
        try await client.rpc(
            "get_saving_ledger_snapshot",
            params: ["p_goal_id": goalID.uuidString]
        ).execute().value
    }

    // ISSUE #80 STAGING ONLY. The project does not define this compilation
    // flag. Neither method exists in the production app build. A later signed
    // client + audited server migration MUST approve any activation.
    #if PIPO_ISSUE80_STAGING
    /// First attempt is persisted BEFORE the authenticated INSERT. If the
    /// request was previously attempted, this method refuses a second INSERT.
    /// Ambiguous insert errors always reconcile by authoritative SELECT.
    func issue80StageOnlySubmitInitialGoal(
        goalID: UUID, authenticatedUserID: UUID,
        journal: SavingGoalCreateIntentJournal
    ) async throws -> PendingSavingGoalCreateIntent.State {
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        let request = try journal.markInsertAttempted(
            goalID: goalID, ownerID: authenticatedUserID
        )
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingGoalCreateJournalError.accountChanged
        }

        // A timeout, PostgREST 409, or dropped socket can occur AFTER the
        // INSERT committed. Never create a fresh UUID or issue an UPSERT.
        // Even on error, proceed to owner-filtered readback; a read error
        // propagates as UNKNOWN while the journal stays attempted.
        do {
            try await issue80InsertGoalOnly(request)
        } catch {
            guard client.auth.currentUser?.id == authenticatedUserID else {
                throw SavingGoalCreateJournalError.accountChanged
            }
            // Intentionally retain exact request and reconcile by SELECT.
        }
        return try await issue80StageOnlyRecoverInitialGoal(
            goalID: goalID, authenticatedUserID: authenticatedUserID,
            journal: journal
        )
    }

    /// After a timeout or relaunch, READ FIRST; never repeat the INSERT.
    /// The caller must not treat a thrown error as cloud-saved.
    func issue80StageOnlyRecoverInitialGoal(
        goalID: UUID, authenticatedUserID: UUID,
        journal: SavingGoalCreateIntentJournal
    ) async throws -> PendingSavingGoalCreateIntent.State {
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        guard try journal.all(for: authenticatedUserID).contains(where: {
            $0.goalID == goalID
        }) else { throw SavingGoalCreateJournalError.unknownGoal }

        let rows = try await issue80FetchOwnedCreateGoal(
            goalID: goalID, ownerID: authenticatedUserID
        )
        guard client.auth.currentUser?.id == authenticatedUserID else {
            throw SavingGoalCreateJournalError.accountChanged
        }
        guard rows.count <= 1 else {
            throw SavingGoalCreateJournalError.untrustedReadback
        }
        return try journal.recordReadback(
            rows.first, goalID: goalID, ownerID: authenticatedUserID,
            authenticatedOwnerID: authenticatedUserID
        )
    }

    private nonisolated func issue80InsertGoalOnly(
        _ request: SavingGoalCreateOnlyRequest
    ) async throws {
        try await client.from("saving_goals")
            .insert(request)
            .execute()
    }

    private nonisolated func issue80FetchOwnedCreateGoal(
        goalID: UUID, ownerID: UUID
    ) async throws -> [SavingGoalAuthoritativeCloudRow] {
        // Decode an array, not single()/maybeSingle(), to distinguish 0
        // matching rows from unexpected duplicates without 406 semantics.
        try await client.from("saving_goals")
            .select("id,user_id,title,category,custom_category,target_amount,currency_code,start_date,target_date,rhythm,preferred_saving_day,planned_contribution_override,plan_revision")
            .eq("id", value: goalID.uuidString)
            .eq("user_id", value: ownerID.uuidString)
            .limit(2)
            .execute()
            .value
    }
    #endif

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
