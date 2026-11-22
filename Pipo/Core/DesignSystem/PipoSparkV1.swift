import SwiftUI

// Issue #68 — standalone Spark is a streak-status icon, NOT a badge or Pipo.
// All icon pixels come from the approved 20 Figma variants exported at 3x.
// Game logic owns the status; this view never infers streaks from money values.
enum PipoSparkState: String, CaseIterable, Sendable {
    case notStarted = "NotStarted"
    case active = "Active"
    case pending = "Pending"
    case ended = "Ended"
    case recovery = "Recovery"
}

enum PipoSparkSize: Int, CaseIterable, Sendable {
    case inline = 16
    case compact = 20
    case standard = 24
    case spotlight = 40

    var points: CGFloat { CGFloat(rawValue) }
}

enum PipoSparkAssets {
    static func imageName(state: PipoSparkState, size: PipoSparkSize) -> String {
        "PipoSparkV1_\(state.rawValue)_\(size.rawValue)"
    }
}

/// A presentation-only contract. Callers MUST supply engine-derived status
/// and the authenticated account's actual goal event count; no fake streaks.
/// The flexible rhythm never carries pending/missed/ended pressure.
struct PipoSparkPresentation: Equatable {
    let state: PipoSparkState
    let label: String
    let accessibilityLabel: String

    static func make(
        rhythm: SavingRhythm,
        proposedState: PipoSparkState,
        recordedSavings: Int,
        consecutivePeriods: Int
    ) -> Self {
        if rhythm == .flexible {
            return Self(
                state: .notStarted,
                label: "Saving at your pace",
                accessibilityLabel: "Flexible saving plan. No streak or deadline required."
            )
        }
        guard recordedSavings > 0, consecutivePeriods > 0 else {
            return Self(
                state: .notStarted,
                label: "Start when ready",
                accessibilityLabel: "No streak yet. Start when ready."
            )
        }
        let count = consecutivePeriods
        let period: String
        switch rhythm {
        case .daily: period = "day"
        case .weekly: period = "week"
        case .biWeekly: period = "two-week period"
        case .monthly: period = "month"
        case .flexible: period = "saving period"
        }
        let countLabel: String = {
            if rhythm == .biWeekly {
                return "\(count) two-week periods"
            }
            return "\(count)-\(period) streak"
        }()
        switch proposedState {
        case .notStarted:
            return Self(state: .notStarted,
                        label: "Start when ready",
                        accessibilityLabel: "Streak not started.")
        case .active:
            return Self(state: .active, label: countLabel,
                        accessibilityLabel: "On track. \(countLabel).")
        case .pending:
            return Self(state: .pending,
                        label: "\(countLabel) · Period still open",
                        accessibilityLabel: "\(countLabel). This saving period is still open; no missed period yet.")
        case .ended:
            return Self(state: .ended, label: "Streak ended",
                        accessibilityLabel: "A prior scheduled period was missed. Your best streak remains saved. Previous \(countLabel).")
        case .recovery:
            return Self(state: .recovery, label: "Back on track · \(countLabel)",
                        accessibilityLabel: "Back on track after a missed scheduled period. New \(countLabel).")
        }
    }
}



/// Issue #69: one projection for Dashboard and Goal Detail. This reads
/// account-owned, persisted goal entries and delegates *all* scheduled-period
/// indexing/counts to SavingConsistency (#14). It never stores streaks,
/// grants XP or interprets account-wide UserProfile.streakDays as a goal value.
@MainActor
enum PipoSparkGoalStatus {
    static func presentation(
        for goal: PersonalGoal,
        transactions: [SavingTransaction],
        userID: UUID?,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> PipoSparkPresentation? {
        guard let owner = userID,
              goal.ownerUserID == owner,
              goal.canRecordSaving, !goal.isGroupGoal else { return nil }

        if goal.rhythm == .flexible {
            return PipoSparkPresentation.make(
                rhythm: .flexible, proposedState: .notStarted,
                recordedSavings: 0, consecutivePeriods: 0
            )
        }

        // A duplicate UUID is not a second saving event. Fail closed rather
        // than displaying a fabricated streak on a corrupt/imported journal.
        let owned = transactions.filter {
            $0.userID == owner && $0.goalId == goal.id &&
            $0.amount > 0 && $0.date <= now
        }
        guard Set(owned.map(\.id)).count == owned.count else {
            return PipoSparkPresentation.make(
                rhythm: goal.rhythm, proposedState: .notStarted,
                recordedSavings: 0, consecutivePeriods: 0
            )
        }

        let dates = owned.map(\.date).filter {
            SavingConsistency.periodIndex(
                for: $0, rhythm: goal.rhythm,
                startDate: goal.startDate, calendar: calendar
            ) != nil
        }
        guard let currentPeriod = SavingConsistency.periodIndex(
            for: now, rhythm: goal.rhythm,
            startDate: goal.startDate, calendar: calendar
        ), !dates.isEmpty else {
            return PipoSparkPresentation.make(
                rhythm: goal.rhythm, proposedState: .notStarted,
                recordedSavings: 0, consecutivePeriods: 0
            )
        }

        let periods = Set(dates.compactMap {
            SavingConsistency.periodIndex(
                for: $0, rhythm: goal.rhythm,
                startDate: goal.startDate, calendar: calendar
            )
        })
        guard let latestPeriod = periods.max(),
              let mostRecentDate = dates.filter({
                  SavingConsistency.periodIndex(
                      for: $0, rhythm: goal.rhythm,
                      startDate: goal.startDate, calendar: calendar
                  ) == latestPeriod
              }).max() else { return nil }

        // For an ended streak, calculate its *historical* length at the last
        // saved event, not a zero count caused by today's missed periods.
        let streak = SavingConsistency.consecutivePeriods(
            dates: dates,
            rhythm: goal.rhythm,
            startDate: goal.startDate,
            asOf: latestPeriod < currentPeriod ? mostRecentDate : now,
            calendar: calendar
        )
        guard streak > 0 else {
            return PipoSparkPresentation.make(
                rhythm: goal.rhythm, proposedState: .notStarted,
                recordedSavings: 0, consecutivePeriods: 0
            )
        }

        let state: PipoSparkState
        if latestPeriod == currentPeriod {
            let prior = periods.filter { $0 < currentPeriod }
            state = prior.max().map { $0 < currentPeriod - 1 } == true
                ? .recovery : .active
        } else if latestPeriod == currentPeriod - 1 {
            // The current period has not ended. Never say a user missed it.
            state = .pending
        } else {
            state = .ended
        }
        return PipoSparkPresentation.make(
            rhythm: goal.rhythm,
            proposedState: state,
            recordedSavings: dates.count,
            consecutivePeriods: streak
        )
    }
}

/// Optically-sized source artwork. Keep the exact asset variants rather than
/// scaling the 40-point asset into small inline glyphs.
struct PipoSparkIcon: View {
    let state: PipoSparkState
    var size: PipoSparkSize = .compact

    var body: some View {
        Image(PipoSparkAssets.imageName(state: state, size: size))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size.points, height: size.points)
            .accessibilityHidden(true) // Chip supplies a complete spoken status.
    }
}

/// Approved Figma Streak Chip V1. Layout grows under Dynamic Type and never
/// relies on pink/grey alone to explain status. No perpetual animations.
struct PipoSparkChip: View {
    let presentation: PipoSparkPresentation

    private var surface: Color {
        switch presentation.state {
        case .active, .recovery: return PipoTheme.palePink
        case .notStarted, .pending, .ended:
            return Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            PipoSparkIcon(state: presentation.state, size: .compact)
            Text(presentation.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.cardInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(surface, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("pipo.spark.chip.\(presentation.state.rawValue)")
    }
}

#Preview("Spark V1 — white and blush") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(PipoSparkState.allCases, id: \.self) { state in
            PipoSparkChip(presentation: .make(
                rhythm: .weekly, proposedState: state,
                recordedSavings: state == .notStarted ? 0 : 4,
                consecutivePeriods: state == .notStarted ? 0 : 4
            ))
        }
        PipoSparkChip(presentation: .make(
            rhythm: .flexible, proposedState: .ended,
            recordedSavings: 10, consecutivePeriods: 0
        ))
    }
    .padding(22)
    .background(Color.white)
}
