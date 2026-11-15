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
        calendar: Calendar = .current
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
        let nextStreak = streakDays(
            afterSavingOn: date,
            lastSavingDate: profile.lastSavingDate,
            currentStreak: profile.streakDays,
            rhythm: goal.rhythm,
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
