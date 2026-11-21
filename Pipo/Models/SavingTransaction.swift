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


// #42: immutable cloud-adjustment projection. No SwiftData schema mutation is
// performed while the proposed server ledger is awaiting security review.
enum SavingAdjustmentKind: String, Codable, Sendable {
    case moneyOut = "money_out"
    case correction
}

struct SavingAdjustmentEvent: Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let kind: SavingAdjustmentKind
    /// moneyOut is a positive subtraction; correction is a signed net delta.
    let amount: Int
    let correctsEventID: UUID?
    let date: Date
}

/// Whole-IDR amounts must remain exactly representable through the existing
/// Supabase Double decoding boundary. This is stricter than numeric(18,2)
/// until the app uses an exact decimal/wire representation end-to-end.
enum SavingsAmountSafety {
    static let maxExactWholeIDR = 9_007_199_254_740_991
}

enum SavingLedgerError: Error, Equatable {
    case unownedRecord
    case duplicateEvent
    case malformedEvent
    case invalidMoney
    case overdrawn
}

struct SavingLedgerSnapshot: Equatable {
    let netRecorded: Int
    let earnedXP: Int

    /// Replays owned contributions and adjustments; the original saving XP
    /// never changes when money is used elsewhere or corrected later.
    static func reconstruct(
        goalID: UUID,
        ownerID: UUID,
        savings: [SavingTransaction],
        adjustments: [SavingAdjustmentEvent]
    ) throws -> SavingLedgerSnapshot {
        guard savings.allSatisfy({ $0.goalId == goalID && $0.userID == ownerID }),
              adjustments.allSatisfy({ $0.goalID == goalID && $0.userID == ownerID })
        else { throw SavingLedgerError.unownedRecord }

        var ids = Set<UUID>()
        var saved = 0
        var earnedXP = 0
        for entry in savings {
            guard ids.insert(entry.id).inserted else { throw SavingLedgerError.duplicateEvent }
            guard let amount = Int(exactly: entry.amount), amount > 0,
                  amount <= SavingsAmountSafety.maxExactWholeIDR, entry.xpEarned >= 0
            else { throw SavingLedgerError.invalidMoney }
            let (next, overflow) = saved.addingReportingOverflow(amount)
            let (xp, xpOverflow) = earnedXP.addingReportingOverflow(entry.xpEarned)
            guard !overflow, !xpOverflow else { throw SavingLedgerError.invalidMoney }
            saved = next
            earnedXP = xp
        }

        // A correction changes an existing money-out amount; it cannot make
        // that recorded usage negative and thereby fabricate saved money.
        // Index originals first so cloud replay is independent of row order.
        var effectiveMoneyOut: [UUID: Int] = [:]
        for event in adjustments where event.kind == .moneyOut {
            guard event.amount > 0, event.correctsEventID == nil
            else { throw SavingLedgerError.malformedEvent }
            effectiveMoneyOut[event.id] = event.amount
        }
        var delta = 0
        for entry in adjustments {
            guard ids.insert(entry.id).inserted else { throw SavingLedgerError.duplicateEvent }
            switch entry.kind {
            case .moneyOut:
                guard entry.amount > 0, entry.correctsEventID == nil
                else { throw SavingLedgerError.malformedEvent }
                guard entry.amount <= SavingsAmountSafety.maxExactWholeIDR
                else { throw SavingLedgerError.invalidMoney }
                let (next, overflow) = delta.subtractingReportingOverflow(entry.amount)
                guard !overflow else { throw SavingLedgerError.invalidMoney }
                delta = next
            case .correction:
                guard entry.amount != 0,
                      entry.amount >= -SavingsAmountSafety.maxExactWholeIDR,
                      entry.amount <= SavingsAmountSafety.maxExactWholeIDR,
                      let original = entry.correctsEventID,
                      let previous = effectiveMoneyOut[original], original != entry.id
                else { throw SavingLedgerError.malformedEvent }
                let (correctedAmount, correctionOverflow) =
                    previous.subtractingReportingOverflow(entry.amount)
                guard !correctionOverflow, correctedAmount > 0
                else { throw SavingLedgerError.malformedEvent }
                effectiveMoneyOut[original] = correctedAmount
                let (next, overflow) = delta.addingReportingOverflow(entry.amount)
                guard !overflow else { throw SavingLedgerError.invalidMoney }
                delta = next
            }
        }
        let (net, overflow) = saved.addingReportingOverflow(delta)
        guard !overflow else { throw SavingLedgerError.invalidMoney }
        guard net >= 0 else { throw SavingLedgerError.overdrawn }
        return .init(netRecorded: net, earnedXP: earnedXP)
    }
}
