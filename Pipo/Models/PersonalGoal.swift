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
    // Optional exact value for new multi-currency breakdown rows.
    var amountMinorUnits: Int64?
    var isCompleted: Bool
    var goal: PersonalGoal?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        amountMinorUnits: Int64? = nil,
        isCompleted: Bool = false,
        goal: PersonalGoal? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.amountMinorUnits = amountMinorUnits
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
    // Legacy local rows predate currencies and are IDR. Optional fields
    // enable SwiftData lightweight migration without touching old history.
    var currencyCode: String?
    var targetMinorUnits: Int64?
    var recordedMinorUnits: Int64?
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
        currencyCode: String? = nil,
        targetMinorUnits: Int64? = nil,
        recordedMinorUnits: Int64? = nil,
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
        self.currencyCode = currencyCode
        self.targetMinorUnits = targetMinorUnits
        self.recordedMinorUnits = recordedMinorUnits
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
        // Exact minor units, not a floating-point cache, decide completion.
        // Original legacy rows fall back only if exact migration is unavailable.
        if let target = exactTargetMinor, let recorded = exactRecordedMinor {
            if target > 0 && recorded >= target { return .completed }
        } else if targetAmount > 0 && currentAmount >= targetAmount {
            return .completed
        }
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

    var effectiveCurrencyCode: String {
        currencyCode == nil ? "IDR" : currencyCode!.uppercased()
    }

    var exactTargetMinor: Int64? {
        targetMinorUnits ?? PipoGoalCurrency.legacyMinor(targetAmount, code: effectiveCurrencyCode)
    }

    var exactRecordedMinor: Int64? {
        recordedMinorUnits ?? PipoGoalCurrency.legacyMinor(currentAmount, code: effectiveCurrencyCode)
    }

    var progress: Double {
        if let target = exactTargetMinor, target > 0, let recorded = exactRecordedMinor {
            let fraction = PipoGoalCurrency.decimal(recorded, code: effectiveCurrencyCode)
                / PipoGoalCurrency.decimal(target, code: effectiveCurrencyCode)
            return min(max(NSDecimalNumber(decimal: fraction).doubleValue, 0), 1)
        }
        guard targetAmount > 0 else { return 0 }
        return min(max(currentAmount / targetAmount, 0), 1)
    }

    var categoryTitle: String {
        customCategory ?? category.title
    }

    var exactRemainingMinor: Int64? {
        guard let target = exactTargetMinor, let recorded = exactRecordedMinor,
              target >= 0, recorded >= 0 else { return nil }
        // Subtracting non-negative Int64 values in this order cannot overflow.
        return target > recorded ? target - recorded : 0
    }

    var remainingAmount: Double {
        if let remaining = exactRemainingMinor {
            return NSDecimalNumber(decimal: PipoGoalCurrency.decimal(
                remaining, code: effectiveCurrencyCode
            )).doubleValue
        }
        return max(targetAmount - currentAmount, 0)
    }
}

 
// MARK: - #42 deterministic financial previews (no writes or XP awards)
//
// These pure calculations deliberately do NOT record a money-out entry.
// An account-owned, idempotent, server-validated ledger must be available
// before the confirmation control can be connected to persisted data.
enum PlanFinancialPreviewError: Error, Equatable {
    case invalidTarget
    case invalidBalance
    case invalidAmount
    case insufficientSavings
    case invalidSchedule
    case invalidBreakdown
}

struct PlanFinancialPreview: Equatable {
    let netRecorded: Int
    let target: Int
    let remaining: Int
    let futurePeriods: Int
    let proposedPerPeriod: Int

    static func revisedTarget(
        netRecorded: Int,
        target: Int,
        futurePeriods: Int,
        breakdown: [Int]? = nil
    ) throws -> PlanFinancialPreview {
        guard netRecorded >= 0,
              netRecorded <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidBalance }
        guard target > 0, target <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidTarget }
        if let breakdown {
            var budgetTotal = 0
            for item in breakdown {
                guard item > 0 else { throw PlanFinancialPreviewError.invalidBreakdown }
                let (next, overflow) = budgetTotal.addingReportingOverflow(item)
                guard !overflow else { throw PlanFinancialPreviewError.invalidBreakdown }
                budgetTotal = next
            }
            guard budgetTotal == target else {
                throw PlanFinancialPreviewError.invalidBreakdown
            }
        }
        guard futurePeriods > 0 else { throw PlanFinancialPreviewError.invalidSchedule }
        let remaining = max(target - netRecorded, 0)
        let perPeriod = remaining / futurePeriods + (remaining % futurePeriods == 0 ? 0 : 1)
        return .init(netRecorded: netRecorded, target: target,
                     remaining: remaining, futurePeriods: futurePeriods,
                     proposedPerPeriod: perPeriod)
    }
}

struct MoneyOutFinancialPreview: Equatable {
    let priorNetRecorded: Int
    let moneyTakenOut: Int
    let revisedNetRecorded: Int
    let target: Int
    let remaining: Int
    let keepDatePerPeriod: Int
    let keepAmountPeriods: Int
    let keepAmountFinalContribution: Int

    static func calculate(
        netRecorded: Int,
        target: Int,
        moneyTakenOut: Int,
        futurePeriods: Int,
        currentPerPeriod: Int
    ) throws -> MoneyOutFinancialPreview {
        guard netRecorded >= 0,
              netRecorded <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidBalance }
        guard target > 0, target <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidTarget }
        guard moneyTakenOut > 0,
              moneyTakenOut <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidAmount }
        guard moneyTakenOut <= netRecorded else { throw PlanFinancialPreviewError.insufficientSavings }
        guard futurePeriods > 0, currentPerPeriod > 0 else {
            throw PlanFinancialPreviewError.invalidSchedule
        }
        let revised = netRecorded - moneyTakenOut
        let remaining = max(target - revised, 0)
        let keepDate = remaining / futurePeriods + (remaining % futurePeriods == 0 ? 0 : 1)
        let periods = remaining / currentPerPeriod + (remaining % currentPerPeriod == 0 ? 0 : 1)
        let finalContribution = periods == 0 ? 0 :
            (remaining % currentPerPeriod == 0 ? currentPerPeriod : remaining % currentPerPeriod)
        return .init(priorNetRecorded: netRecorded, moneyTakenOut: moneyTakenOut,
                     revisedNetRecorded: revised, target: target, remaining: remaining,
                     keepDatePerPeriod: keepDate, keepAmountPeriods: periods,
                     keepAmountFinalContribution: finalContribution)
    }
}


/// A correction replaces the *effect* of a previous money-out entry without
/// fabricating a new saving or mutating historical XP. Preview only.
struct MoneyOutCorrectionPreview: Equatable {
    let correctedNetRecorded: Int
    let adjustmentDelta: Int

    static func calculate(
        currentNetRecorded: Int,
        originalMoneyOut: Int,
        correctedMoneyOut: Int
    ) throws -> MoneyOutCorrectionPreview {
        guard currentNetRecorded >= 0,
              currentNetRecorded <= SavingsAmountSafety.maxExactWholeIDR
        else { throw PlanFinancialPreviewError.invalidBalance }
        guard originalMoneyOut > 0, correctedMoneyOut > 0,
              originalMoneyOut <= SavingsAmountSafety.maxExactWholeIDR,
              correctedMoneyOut <= SavingsAmountSafety.maxExactWholeIDR else {
            throw PlanFinancialPreviewError.invalidAmount
        }
        // Reversal is positive when the original money-out was overstated.
        let (delta, overflow) = originalMoneyOut.subtractingReportingOverflow(correctedMoneyOut)
        guard !overflow else { throw PlanFinancialPreviewError.invalidAmount }
        let (net, netOverflow) = currentNetRecorded.addingReportingOverflow(delta)
        guard !netOverflow, net >= 0 else { throw PlanFinancialPreviewError.insufficientSavings }
        return .init(correctedNetRecorded: net, adjustmentDelta: delta)
    }
}
