import Foundation

enum GamificationError: LocalizedError {
    case invalidDepositAmount
    case depositBeforeLastSaving
    case valueOutOfRange

    var errorDescription: String? {
        switch self {
        case .invalidDepositAmount:
            return "Enter a valid saving amount greater than zero."
        case .depositBeforeLastSaving:
            return "A saving cannot be recorded before the previous saving."
        case .valueOutOfRange:
            return "The saving total or XP total is too large to record."
        }
    }
}

struct GamificationManager {
    static let xpPerSaving = 300
    static let xpPerLevel = 1_500

    func recordSaving(
        amount: Double,
        goal: PersonalGoal,
        profile: UserProfile,
        date: Date = .now,
        calendar: Calendar = .current,
        priorTransactions: [SavingTransaction] = []
    ) throws -> SavingTransaction {
        guard amount.isFinite, amount > 0 else {
            throw GamificationError.invalidDepositAmount
        }
        if let lastSavingDate = profile.lastSavingDate, date < lastSavingDate {
            throw GamificationError.depositBeforeLastSaving
        }

        let (nextTotalXP, xpOverflow) = profile.totalXP.addingReportingOverflow(Self.xpPerSaving)
        let nextCurrentAmount = goal.currentAmount + amount
        guard !xpOverflow, nextCurrentAmount.isFinite else {
            throw GamificationError.valueOutOfRange
        }
        // Always derive consistency from the current goal's history.
        // Never carry a streak across goals or rhythms through UserProfile.
        let nextStreak = SavingConsistency.consecutivePeriods(
            dates: priorTransactions.filter { $0.goalId == goal.id }.map(\.date) + [date],
            rhythm: goal.rhythm,
            startDate: goal.startDate,
            asOf: date,
            calendar: calendar
        )

        profile.totalXP = nextTotalXP
        profile.currentLevel = level(for: nextTotalXP)
        profile.streakDays = nextStreak
        profile.lastSavingDate = date
        goal.currentAmount = nextCurrentAmount

        return SavingTransaction(
            goalId: goal.id,
            amount: amount,
            xpEarned: Self.xpPerSaving,
            date: date
        )
    }

    func level(for totalXP: Int) -> Int {
        max(totalXP, 0) / Self.xpPerLevel + 1
    }

    // Historical API retained only for existing migration/unit compatibility.
    // Production goal and widget consistency uses SavingConsistency below.
    func streakDays(
        afterSavingOn date: Date,
        lastSavingDate: Date?,
        currentStreak: Int,
        rhythm: SavingRhythm,
        calendar: Calendar = .current
    ) -> Int {
        guard let lastSavingDate else { return 1 }
        guard date > lastSavingDate else { return max(currentStreak, 1) }
        if calendar.isDate(date, inSameDayAs: lastSavingDate) {
            return max(currentStreak, 1)
        }

        let cadence: (component: Calendar.Component, value: Int)
        switch rhythm {
        case .daily:
            cadence = (.day, 1)
        case .weekly:
            cadence = (.day, 7)
        case .biWeekly:
            cadence = (.day, 14)
        case .monthly, .flexible:
            cadence = (.month, 1)
        }

        guard
            let dueDate = calendar.date(
                byAdding: cadence.component,
                value: cadence.value,
                to: calendar.startOfDay(for: lastSavingDate)
            ),
            let endOfDueDate = calendar.date(byAdding: .day, value: 1, to: dueDate),
            date < endOfDueDate
        else {
            return 1
        }
        return max(currentStreak, 1) + 1
    }
}


/// The single, goal-specific source of truth for progress consistency.
/// Each scheduled saving period counts at most once, even with extra deposits.
/// A period is pending until the next one ends; it is never a daily-login streak.
enum SavingConsistency {
    static func periodIndex(
        for date: Date,
        rhythm: SavingRhythm,
        startDate: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard rhythm != .flexible else { return nil }
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        guard day >= start else { return nil }
        switch rhythm {
        case .daily:
            return calendar.dateComponents([.day], from: start, to: day).day
        case .weekly, .biWeekly:
            guard let days = calendar.dateComponents([.day], from: start, to: day).day else {
                return nil
            }
            return days / (rhythm == .weekly ? 7 : 14)
        case .monthly:
            guard let startMonth = calendar.dateInterval(of: .month, for: start)?.start,
                  let thisMonth = calendar.dateInterval(of: .month, for: day)?.start
            else { return nil }
            return calendar.dateComponents([.month], from: startMonth, to: thisMonth).month
        case .flexible:
            return nil
        }
    }

    static func consecutivePeriods(
        dates: [Date],
        rhythm: SavingRhythm,
        startDate: Date,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let current = periodIndex(
            for: now, rhythm: rhythm, startDate: startDate, calendar: calendar
        ) else { return 0 }
        let completed = Set(dates.compactMap { date -> Int? in
            guard date <= now else { return nil }
            return periodIndex(for: date, rhythm: rhythm, startDate: startDate, calendar: calendar)
        })
        guard let recent = completed.max(), recent >= current - 1 else { return 0 }
        var index = recent
        var count = 0
        while completed.contains(index) {
            count += 1
            index -= 1
        }
        return count
    }

    /// A recovery requires recorded activity before a fully missed period.
    static func isRecovery(
        priorDates: [Date],
        newDate: Date,
        rhythm: SavingRhythm,
        startDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let current = periodIndex(for: newDate, rhythm: rhythm, startDate: startDate, calendar: calendar)
        else { return false }
        let previous = priorDates.compactMap {
            periodIndex(for: $0, rhythm: rhythm, startDate: startDate, calendar: calendar)
        }.filter { $0 < current }
        guard let mostRecent = previous.max() else { return false }
        return mostRecent < current - 1
    }

    /// Used only for badge rules needing the exact date chosen in the plan.
    static func isPlannedContribution(
        date: Date, amount: Double, goal: PersonalGoal, calendar: Calendar = .current
    ) -> Bool {
        guard goal.rhythm != .flexible, amount > 0,
              goal.targetAmount >= 1,
              goal.targetAmount < Double(Int.max),
              let schedule = PersonalSavingSchedule(
                targetAmount: Int(goal.targetAmount),
                startDate: goal.startDate,
                targetDate: goal.targetDate,
                rhythm: goal.rhythm,
                preferredDay: goal.preferredSavingDay,
                calendar: calendar
              ) else { return false }
        let amountDue = Double(goal.plannedContributionOverride ?? schedule.amount)
        guard amount >= amountDue, amountDue > 0 else { return false }
        let target = calendar.startOfDay(for: date)
        guard target >= schedule.firstDate, target <= schedule.lastDate else { return false }

        switch goal.rhythm {
        case .daily, .weekly, .biWeekly:
            let gap = goal.rhythm == .daily ? 1 : (goal.rhythm == .weekly ? 7 : 14)
            guard let days = calendar.dateComponents([.day], from: schedule.firstDate, to: target).day
            else { return false }
            return days >= 0 && days % gap == 0
        case .monthly:
            // The 31st becomes the final day in shorter months.
            guard let monthStart = calendar.dateInterval(of: .month, for: target)?.start,
                  let range = calendar.range(of: .day, in: .month, for: target),
                  let day = calendar.date(byAdding: .day,
                    value: min(goal.preferredSavingDay ?? calendar.component(.day, from: goal.startDate),
                               range.count) - 1, to: monthStart)
            else { return false }
            return calendar.isDate(day, inSameDayAs: target)
        case .flexible:
            return false
        }
    }
}

/// Names and triggers follow the approved Figma 17-badge collection.
enum PipoBadge: String, CaseIterable, Identifiable {
    case firstSave = "first-save"
    case planMatch = "plan-match"
    case plannedThree = "3-planned"
    case periodsFour = "4-periods"
    case recovery = "recovery"
    case extraSave = "extra-save"
    case realisticPlan = "adapt-go"
    case nextGoal = "next-goal"
    case quarterWay = "quarter-way"
    case halfway = "halfway"
    case almostThere = "almost-there"
    case goalAchieved = "goal-achieved"
    case savingTogether = "saving-together"
    case supportiveFriend = "supportive-friend"
    case pipoGrows = "pipo-grows"
    case seasonalSaver = "seasonal-saver"
    case multiGoal = "multi-goal"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstSave: "First Step"
        case .planMatch: "Plan in Action"
        case .plannedThree: "Building Consistency"
        case .periodsFour: "Rhythm Established"
        case .recovery: "Back on Track"
        case .extraSave: "Goal Bonus"
        case .realisticPlan: "Realistic Plan"
        case .nextGoal: "Next Goal"
        case .quarterWay: "Quarter Way"
        case .halfway: "Halfway There"
        case .almostThere: "Almost There"
        case .goalAchieved: "Goal Achieved"
        case .savingTogether: "Saving Together"
        case .supportiveFriend: "Supportive Friend"
        case .pipoGrows: "Pipo Grows"
        case .seasonalSaver: "Seasonal Saver"
        case .multiGoal: "Multi-Goal Planner"
        }
    }
    var description: String {
        switch self {
        case .firstSave: "Record your first saving contribution."
        case .planMatch: "Record a contribution matching your planned day and amount."
        case .plannedThree: "Complete three planned contributions toward one goal."
        case .periodsFour: "Contribute through four consecutive planned periods."
        case .recovery: "Save again after missing a planned period."
        case .extraSave: "Record an extra contribution beyond the planned schedule."
        case .realisticPlan: "Revise an unrealistic plan and continue saving."
        case .nextGoal: "Start another goal after reaching one."
        case .quarterWay: "Reach 25% of a saving goal."
        case .halfway: "Reach 50% of a saving goal."
        case .almostThere: "Reach 75% of a saving goal."
        case .goalAchieved: "Reach 100% of a saving goal."
        case .savingTogether: "Reach a verified group saving milestone."
        case .supportiveFriend: "Encourage a real group member."
        case .pipoGrows: "Build a sustained saving habit."
        case .seasonalSaver: "Keep saving across three calendar months."
        case .multiGoal: "Contribute consistently to multiple goals."
        }
    }
    var symbol: String {
        switch self {
        case .firstSave: "figure.walk"
        case .planMatch: "calendar.badge.checkmark"
        case .plannedThree: "checkmark.seal"
        case .periodsFour: "flame"
        case .recovery: "arrow.uturn.backward.circle"
        case .extraSave: "plus.circle"
        case .realisticPlan: "slider.horizontal.3"
        case .nextGoal: "arrow.forward.circle"
        case .quarterWay, .halfway, .almostThere, .goalAchieved: "target"
        case .savingTogether: "person.2.fill"
        case .supportiveFriend: "heart"
        case .pipoGrows: "leaf"
        case .seasonalSaver: "calendar"
        case .multiGoal: "square.grid.2x2"
        }
    }
    /// Incomplete product workflows cannot earn badges by inference.
    var isImplemented: Bool {
        switch self {
        case .realisticPlan, .nextGoal, .savingTogether, .supportiveFriend,
             .pipoGrows, .seasonalSaver, .multiGoal: false
        default: true
        }
    }
}

/// Grants only evidence-backed, persisted awards from this account and goal.
/// Call before the same SwiftData save as the transaction, and roll back on failure.
enum AchievementEngine {
    @discardableResult
    static func grant(
        profile: UserProfile,
        goal: PersonalGoal,
        transaction: SavingTransaction,
        history: [SavingTransaction],
        previousAmount: Double,
        calendar: Calendar = .current
    ) -> [PipoBadge] {
        guard let userID = profile.userID,
              goal.ownerUserID == userID,
              transaction.userID == userID,
              transaction.goalId == goal.id else { return [] }
        let existing = history.filter { $0.userID == userID && $0.goalId == goal.id &&
            $0.id != transaction.id && $0.date <= transaction.date }
        let priorDates = existing.map(\.date)
        let all = existing + [transaction]
        let allDates = all.map(\.date)
        let planned = all.filter {
            SavingConsistency.isPlannedContribution(date: $0.date, amount: $0.amount,
                                                    goal: goal, calendar: calendar)
        }
        let uniquePlannedDays = Set(planned.map { calendar.startOfDay(for: $0.date) })
        let periods = SavingConsistency.consecutivePeriods(
            dates: allDates, rhythm: goal.rhythm, startDate: goal.startDate,
            asOf: transaction.date, calendar: calendar
        )

        var eligible: [PipoBadge] = [.firstSave]
        if SavingConsistency.isPlannedContribution(date: transaction.date,
                                                  amount: transaction.amount,
                                                  goal: goal, calendar: calendar) {
            eligible.append(.planMatch)
        }
        if uniquePlannedDays.count >= 3 { eligible.append(.plannedThree) }
        if periods >= 4 { eligible.append(.periodsFour) }
        if SavingConsistency.isRecovery(priorDates: priorDates, newDate: transaction.date,
                                       rhythm: goal.rhythm, startDate: goal.startDate,
                                       calendar: calendar) { eligible.append(.recovery) }
        if !existing.isEmpty &&
            !SavingConsistency.isPlannedContribution(date: transaction.date, amount: transaction.amount,
                                                     goal: goal, calendar: calendar) {
            eligible.append(.extraSave)
        }
        for (badge, threshold) in [
            (PipoBadge.quarterWay, 0.25), (.halfway, 0.50),
            (.almostThere, 0.75), (.goalAchieved, 1.00)
        ] {
            guard goal.targetAmount > 0 else { continue }
            let oldProgress = previousAmount / goal.targetAmount
            let newProgress = goal.currentAmount / goal.targetAmount
            if oldProgress < threshold && newProgress >= threshold {
                eligible.append(badge)
            }
        }
        let oldSet = Set(profile.unlockedBadgeIds)
        let unlocked = eligible.filter { $0.isImplemented && !oldSet.contains($0.rawValue) }
        if !unlocked.isEmpty {
            profile.unlockedBadgeIds += unlocked.map(\.rawValue)
        }
        return unlocked
    }
}
