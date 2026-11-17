import Foundation
import SwiftUI

@MainActor
struct SavingRhythmView: View {
    let goalTitle: String
    let targetAmount: Double
    let plannedStartDate: Date
    let targetDate: Date

    @State private var selectedRhythm: SavingRhythm
    @State private var preferredDepositDay: Int

    private let onBack: () -> Void
    private let onEditContribution: () -> Void
    private let onContinue: (SavingRhythm, Int, Double) -> Void

    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    init(
        goalTitle: String,
        targetAmount: Double,
        plannedStartDate: Date,
        targetDate: Date,
        selectedRhythm: SavingRhythm = .monthly,
        preferredDepositDay: Int = 25,
        onBack: @escaping () -> Void,
        onEditContribution: @escaping () -> Void,
        onContinue: @escaping (SavingRhythm, Int, Double) -> Void
    ) {
        self.goalTitle = goalTitle
        self.targetAmount = targetAmount
        self.plannedStartDate = plannedStartDate
        self.targetDate = targetDate
        _selectedRhythm = State(initialValue: selectedRhythm)
        _preferredDepositDay = State(initialValue: min(max(preferredDepositDay, 1), 31))
        self.onBack = onBack
        self.onEditContribution = onEditContribution
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    navigationHeader
                    intro
                    rhythmPicker
                    depositDatePicker
                    contributionEstimate
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .preferredColorScheme(.light)
    }

    private var navigationHeader: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(PipoTheme.cream, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Personal saving plan")
                .font(.headline.weight(.semibold))
                .foregroundStyle(PipoTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("4 of 5")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.muted)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(progressColor(for: index))
                        .frame(height: 5)
                }
            }
            .offset(y: 24)
        }
        .padding(.bottom, 24)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Text("🎯")
                .font(.system(size: 72))
                .padding(.top, 12)
                .accessibilityHidden(true)
            Text("What’s your saving rhythm?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.ink)
            Text("Set a target for \(goalTitle).")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    private var rhythmPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saving frequency · Required")
                .font(.headline.weight(.medium))
                .foregroundStyle(PipoTheme.muted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SavingRhythm.allCases) { rhythm in
                    rhythmOption(rhythm)
                        .gridCellColumns(rhythm == .flexible ? 2 : 1)
                }
            }
        }
    }

    private func rhythmOption(_ rhythm: SavingRhythm) -> some View {
        let isSelected = selectedRhythm == rhythm
        return Button {
            selectedRhythm = rhythm
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? PipoTheme.pink : PipoTheme.muted.opacity(0.7))
                Text(rhythm.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? PipoTheme.deepPink : PipoTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? PipoTheme.palePink : PipoTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? PipoTheme.pink : PipoTheme.border, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var depositDatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferred saving date")
                .font(.title3.weight(.bold))
                .foregroundStyle(PipoTheme.ink)

            LazyVGrid(columns: dayColumns, spacing: 8) {
                ForEach(1...31, id: \.self) { day in
                    Button {
                        preferredDepositDay = day
                    } label: {
                        Text("\(day)")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(preferredDepositDay == day ? .white : PipoTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                preferredDepositDay == day ? PipoTheme.pink : PipoTheme.cream,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Day \(day)")
                    .accessibilityAddTraits(preferredDepositDay == day ? .isSelected : [])
                }
            }

            Text("On the \(ordinal(preferredDepositDay)). If unavailable, use the month’s last day.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
        }
    }

    private var contributionEstimate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedRhythm == .flexible ? "Suggested contribution" : "Planned contribution")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                Spacer()
                Text("Required")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.muted)
            }

            HStack {
                Text(plannedContributionAmount, format: .currency(code: "IDR").locale(Locale(identifier: "id_ID")).precision(.fractionLength(0)))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(PipoTheme.ink)
                Spacer()
                Text(selectedRhythm.unitLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.muted)
                Button(action: onEditContribution) {
                    Image(systemName: "pencil")
                        .font(.title3)
                        .foregroundStyle(PipoTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit planned contribution")
            }
            .padding(16)
            .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PipoTheme.border, lineWidth: 1)
            }

            Text("Suggested estimate · change this amount anytime")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PipoTheme.deepPink)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(contributionDates.count) \(selectedRhythm.periodLabel)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PipoTheme.deepPink)
                Text(scheduleSummary)
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Back", action: onBack)
                .buttonStyle(SecondaryActionButtonStyle())
            Button("Continue") {
                onContinue(selectedRhythm, preferredDepositDay, plannedContributionAmount)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.55)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.white)
        .overlay(alignment: .top) {
            PipoTheme.border.frame(height: 1)
        }
    }

    private var plannedContributionAmount: Double {
        let count = contributionDates.count
        guard count > 0, targetAmount > 0 else { return 0 }
        return targetAmount / Double(count)
    }

    private var canContinue: Bool {
        targetAmount > 0 && !contributionDates.isEmpty
    }

    private var contributionDates: [Date] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: plannedStartDate)
        let endDay = calendar.startOfDay(for: targetDate)
        guard startDay <= endDay else { return [] }

        if selectedRhythm == .monthly || selectedRhythm == .flexible {
            guard
                let firstMonth = calendar.dateInterval(of: .month, for: startDay)?.start,
                let lastMonth = calendar.dateInterval(of: .month, for: endDay)?.start
            else {
                return []
            }
            let monthCount = calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0
            guard monthCount >= 0 else { return [] }

            return (0...monthCount).compactMap { offset in
                guard
                    let monthDate = calendar.date(byAdding: .month, value: offset, to: firstMonth),
                    let dayRange = calendar.range(of: .day, in: .month, for: monthDate)
                else {
                    return nil
                }
                let components = calendar.dateComponents([.year, .month], from: monthDate)
                let day = min(preferredDepositDay, dayRange.count)
                guard let date = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)) else {
                    return nil
                }
                return date >= startDay && date <= endDay ? date : nil
            }
        }

        let interval: Int
        switch selectedRhythm {
        case .daily: interval = 1
        case .weekly: interval = 7
        case .biWeekly: interval = 14
        case .monthly, .flexible: interval = 1
        }
        let days = max(calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0, 0)
        let count = days / interval + 1
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: index * interval, to: startDay)
        }
    }

    private var scheduleSummary: String {
        guard let first = contributionDates.first, let last = contributionDates.last else {
            return "Choose a target date after your planned start date."
        }
        let dateFormat = Date.FormatStyle.dateTime
            .day()
            .month(.wide)
            .year()
            .locale(Locale(identifier: "en_GB"))
        let firstDate = first.formatted(dateFormat)
        let lastDate = last.formatted(dateFormat)
        let amount = plannedContributionAmount.formatted(
            .currency(code: "IDR").locale(Locale(identifier: "id_ID")).precision(.fractionLength(0))
        )
        let total = targetAmount.formatted(
            .currency(code: "IDR").locale(Locale(identifier: "id_ID")).precision(.fractionLength(0))
        )
        return "Planned start: \(firstDate). Last planned save: \(lastDate). \(contributionDates.count) × \(amount) = \(total), starting from Rp0. An estimate, not financial advice."
    }

    private func progressColor(for index: Int) -> Color {
        if index < 3 { return PipoTheme.green }
        if index == 3 { return PipoTheme.pink }
        return PipoTheme.border
    }

    private func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11...13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

extension SavingRhythm {
    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biWeekly: "Every two weeks"
        case .monthly: "Monthly"
        case .flexible: "Flexible · save when you can"
        }
    }

    var unitLabel: String {
        switch self {
        case .daily: " / day"
        case .weekly: " / week"
        case .biWeekly: " / 2 weeks"
        case .monthly: " / month"
        case .flexible: " / deposit"
        }
    }

    var periodLabel: String {
        switch self {
        case .daily: "daily contributions"
        case .weekly: "weekly contributions"
        case .biWeekly: "contributions every two weeks"
        case .monthly: "monthly contributions"
        case .flexible: "suggested monthly contributions"
        }
    }
}

#Preview {
    SavingRhythmView(
        goalTitle: MockData.savingGoalTitle,
        targetAmount: MockData.savingGoalTarget,
        plannedStartDate: MockData.savingStartDate,
        targetDate: MockData.savingTargetDate,
        onBack: {},
        onEditContribution: {},
        onContinue: { _, _, _ in }
    )
}
