import Foundation
import SwiftUI

// Manage Plan V2 Option B — a local, unsaved plan draft. No SwiftData writes,
// Supabase mutations, XP awards, or bank operations are allowed in this file.
enum PipoPlanV2Money {
    static let maximum = Decimal(9_007_199_254_740_991)

    static func fractionDigits(for currency: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        // NSNumber/ISO 4217 currency metadata, not an IDR-only integer parser.
        return min(max(formatter.maximumFractionDigits, 0), 3)
    }

    static func locale(for currency: String) -> Locale {
        currency == "IDR" ? Locale(identifier: "id_ID") : Locale.current
    }

    static func parse(_ raw: String, currency: String, locale: Locale? = nil) -> Decimal? {
        let locale = locale ?? self.locale(for: currency)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let parts = trimmed.components(separatedBy: decimalSeparator)
        guard (1...2).contains(parts.count), let whole = parts.first, !whole.isEmpty else {
            return nil
        }
        let groups = whole.components(separatedBy: groupingSeparator)
        func onlyASCII(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
        }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), onlyASCII(groups[0]),
                  groups.dropFirst().allSatisfy({ $0.count == 3 && onlyASCII($0) })
            else { return nil }
        } else {
            guard onlyASCII(whole) else { return nil }
        }
        let digits = groups.joined()
        let fraction = parts.count == 2 ? parts[1] : ""
        let precision = fractionDigits(for: currency)
        guard (fraction.isEmpty && parts.count == 1)
                || (!fraction.isEmpty && fraction.count <= precision && onlyASCII(fraction))
        else { return nil }
        let normalized = digits + (fraction.isEmpty ? "" : "." + fraction)
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= maximum
        else { return nil }
        return value
    }

    static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite, value >= 0,
              let result = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")),
              result <= maximum
        else { return nil }
        return result
    }

    static func editable(_ value: Decimal, currency: String) -> String {
        let raw = NSDecimalNumber(decimal: value).stringValue
        return raw.replacingOccurrences(of: ".", with: locale(for: currency).decimalSeparator ?? ".")
    }

    static func formatted(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale(for: currency)
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = fractionDigits(for: currency)
        formatter.maximumFractionDigits = fractionDigits(for: currency)
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue + " " + currency
    }

    static func suggested(_ remaining: Decimal, periods: Int, currency: String) -> Decimal? {
        guard periods > 0, remaining >= 0 else { return nil }
        var input = remaining / Decimal(periods)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, fractionDigits(for: currency), .up)
        return rounded
    }
}

struct PipoPlanV2Budget: Identifiable, Equatable {
    let id: UUID
    var title: String
    var input: String
}

struct PipoPlanV2Original: Equatable {
    let title: String
    let target: Decimal
    let recorded: Decimal
    let targetDate: Date
    let startDate: Date
    let rhythm: SavingRhythm
    let preferredDay: Int?
    let budget: [PipoPlanV2Budget]
    // Existing stored goals have no currency column; legacy rows are IDR.
    // This value MUST NOT be exposed as a selectable/exchangeable currency.
    let currency: String

    @MainActor
    init(goal: PersonalGoal) {
        title = goal.title
        target = PipoPlanV2Money.decimal(goal.targetAmount) ?? 0
        recorded = PipoPlanV2Money.decimal(goal.currentAmount) ?? 0
        targetDate = goal.targetDate
        startDate = goal.startDate
        rhythm = goal.rhythm
        let calendar = Calendar.current
        if rhythm == .weekly || rhythm == .biWeekly {
            preferredDay = goal.preferredSavingDay ??
                calendar.component(.weekday, from: goal.startDate)
        } else if rhythm == .monthly {
            preferredDay = goal.preferredSavingDay ??
                calendar.component(.day, from: goal.startDate)
        } else {
            preferredDay = nil
        }
        currency = "IDR"
        budget = goal.subItems.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map {
                PipoPlanV2Budget(
                    id: $0.id, title: $0.title,
                    input: PipoPlanV2Money.editable(
                        PipoPlanV2Money.decimal($0.amount) ?? 0, currency: "IDR"
                    )
                )
            }
    }
}

enum PipoPlanV2Cadence {
    // Strictly future events; the original start date anchors biweekly parity.
    // Calendar calculations use the user's local timezone and month lengths.
    static func remainingCount(
        originalStart: Date,
        finish: Date,
        rhythm: SavingRhythm,
        preferredDay: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        if rhythm == .flexible { return nil }
        guard let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ) else { return 0 }
        let start = max(calendar.startOfDay(for: originalStart), tomorrow)
        let end = calendar.startOfDay(for: finish)
        guard start <= end else { return 0 }
        switch rhythm {
        case .daily:
            guard let days = calendar.dateComponents([.day], from: start, to: end).day
            else { return 0 }
            return days + 1
        case .weekly, .biWeekly:
            guard let weekday = preferredDay, (1...7).contains(weekday) else { return 0 }
            let anchor = calendar.startOfDay(for: originalStart)
            let firstOffset = (weekday - calendar.component(.weekday, from: anchor) + 7) % 7
            guard var date = calendar.date(byAdding: .day, value: firstOffset, to: anchor)
            else { return 0 }
            let stride = rhythm == .weekly ? 7 : 14
            // No unbounded loop for malformed multi-century legacy dates.
            var iterations = 0
            while date < start && iterations < 20_000 {
                guard let next = calendar.date(byAdding: .day, value: stride, to: date)
                else { return 0 }
                date = next
                iterations += 1
            }
            guard date >= start else { return 0 }
            var count = 0
            while date <= end && count < 20_000 {
                count += 1
                guard let next = calendar.date(byAdding: .day, value: stride, to: date)
                else { break }
                date = next
            }
            return count
        case .monthly:
            guard let day = preferredDay, (1...31).contains(day),
                  var month = calendar.dateInterval(of: .month, for: start)?.start
            else { return 0 }
            var count = 0
            while month <= end && count < 20_000 {
                guard let range = calendar.range(of: .day, in: .month, for: month),
                      let date = calendar.date(
                        byAdding: .day, value: min(day, range.count) - 1, to: month
                      ),
                      let next = calendar.date(byAdding: .month, value: 1, to: month)
                else { break }
                if date >= start && date <= end { count += 1 }
                month = next
            }
            return count
        case .flexible:
            return nil
        }
    }
}

struct PipoPlanV2Draft: Equatable {
    let original: PipoPlanV2Original
    var targetInput: String
    var budget: [PipoPlanV2Budget]
    var finishDate: Date
    var rhythm: SavingRhythm
    var preferredDay: Int?

    init(original: PipoPlanV2Original) {
        self.original = original
        targetInput = PipoPlanV2Money.editable(original.target, currency: original.currency)
        budget = original.budget
        finishDate = original.targetDate
        rhythm = original.rhythm
        preferredDay = original.preferredDay
    }

    var target: Decimal? {
        PipoPlanV2Money.parse(targetInput, currency: original.currency)
    }

    private func normalized(_ rows: [PipoPlanV2Budget]) -> [(String, Decimal?)] {
        rows.map {
            ($0.title.trimmingCharacters(in: .whitespacesAndNewlines),
             PipoPlanV2Money.parse($0.input, currency: original.currency))
        }
    }

    var isDirty: Bool {
        let targetChanged = target.map { $0 != original.target } ??
            (targetInput != PipoPlanV2Money.editable(original.target, currency: original.currency))
        let left = normalized(budget)
        let right = normalized(original.budget)
        let budgetChanged = left.count != right.count ||
            zip(left, right).contains { a, b in a.0 != b.0 || a.1 != b.1 }
        let dateChanged = !Calendar.current.isDate(finishDate, inSameDayAs: original.targetDate)
        let rhythmChanged = rhythm != original.rhythm ||
            ((rhythm != .flexible && rhythm != .daily) &&
             preferredDay != original.preferredDay)
        return targetChanged || budgetChanged || dateChanged || rhythmChanged
    }

    var allocationTotal: Decimal? {
        if budget.isEmpty { return nil }
        var total: Decimal = 0
        for row in budget {
            guard !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let amount = PipoPlanV2Money.parse(row.input, currency: original.currency)
            else { return nil }
            total += amount
        }
        return total
    }

    var validationError: String? {
        guard let target else {
            return "Enter a positive amount with the correct currency precision."
        }
        guard target >= original.recorded else {
            return "This target is below what you've already recorded. Your saving history cannot be rewritten."
        }
        if !budget.isEmpty {
            guard let allocationTotal else {
                return "Every budget item needs a name and a valid positive amount."
            }
            if allocationTotal != target {
                let difference = target - allocationTotal
                return difference > 0
                    ? "Allocate " + PipoPlanV2Money.formatted(difference, currency: original.currency) + " more to match the target."
                    : "Your budget exceeds the target by " +
                        PipoPlanV2Money.formatted(-difference, currency: original.currency) + "."
            }
        }
        guard Calendar.current.startOfDay(for: finishDate) >
            Calendar.current.startOfDay(for: .now)
        else { return "Choose a future finish date." }
        if rhythm == .weekly || rhythm == .biWeekly {
            guard let preferredDay, (1...7).contains(preferredDay)
            else { return "Choose a preferred weekday." }
        }
        if rhythm == .monthly {
            guard let preferredDay, (1...31).contains(preferredDay)
            else { return "Choose a preferred calendar day." }
        }
        if rhythm != .flexible {
            guard let count = PipoPlanV2Cadence.remainingCount(
                originalStart: original.startDate, finish: finishDate,
                rhythm: rhythm, preferredDay: preferredDay
            ), count > 0 else {
                return "No future saving dates are available before this finish date."
            }
        }
        return nil
    }

    var remaining: Decimal? {
        target.map { max($0 - original.recorded, 0) }
    }

    func suggested(now: Date = .now, calendar: Calendar = .current) -> Decimal? {
        guard let remaining,
              let count = PipoPlanV2Cadence.remainingCount(
                originalStart: original.startDate, finish: finishDate,
                rhythm: rhythm, preferredDay: preferredDay,
                now: now, calendar: calendar
              )
        else { return nil }
        return PipoPlanV2Money.suggested(remaining, periods: count, currency: original.currency)
    }

    func priorSuggestion(now: Date = .now, calendar: Calendar = .current) -> Decimal? {
        let remaining = max(original.target - original.recorded, 0)
        guard let count = PipoPlanV2Cadence.remainingCount(
            originalStart: original.startDate, finish: original.targetDate,
            rhythm: original.rhythm, preferredDay: original.preferredDay,
            now: now, calendar: calendar
        ) else { return nil }
        return PipoPlanV2Money.suggested(remaining, periods: count, currency: original.currency)
    }
}

@MainActor
struct PipoManagePlanV2Sheet: View {
    let onClose: () -> Void
    @State private var draft: PipoPlanV2Draft
    @State private var step: Step = .overview
    @State private var returnEditor: Step = .target
    @State private var askDiscard = false
    @FocusState private var focusedInput: String?

    init(goal: PersonalGoal, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _draft = State(initialValue: PipoPlanV2Draft(original: PipoPlanV2Original(goal: goal)))
    }

    private enum Step: Equatable {
        case overview, target, breakdown, date, rhythm, impact, review
    }

    private var original: PipoPlanV2Original { draft.original }
    private var currency: String { original.currency }
    private func money(_ value: Decimal) -> String {
        PipoPlanV2Money.formatted(value, currency: currency)
    }

    private var heading: String {
        switch step {
        case .overview: "Your plan, your pace."
        case .target: "Change the target."
        case .breakdown: "Balance your budget."
        case .date: "Change the finish date."
        case .rhythm: draft.rhythm == .flexible ? "Save when it feels right." : "Find your pace."
        case .impact: "Here's what changes."
        case .review: "Review your new plan."
        }
    }

    private var subtitle: String {
        switch step {
        case .overview: original.title + " · What do you want to adjust?"
        case .target: "Only the future plan changes."
        case .breakdown: "Match your categories to the proposed target."
        case .date: "Give your goal a little more time."
        case .rhythm: "Updates begin next saving period."
        case .impact: "Take a look before deciding."
        case .review: "A secure save isn't available yet."
        }
    }

    private var canPreview: Bool { draft.isDirty && draft.validationError == nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let horizontal: CGFloat = geometry.size.width <= 350 ? 16 : 20
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, horizontal)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(heading)
                                    .font(.title2.bold())
                                    .foregroundStyle(PipoTheme.cardInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(PipoTheme.cardMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 15)
                            content
                            if step != .review {
                                Text("Nothing changes in your saved records until a secure save is available.")
                                    .font(.footnote)
                                    .foregroundStyle(PipoTheme.cardMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, horizontal)
                        .padding(.bottom, 22)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    footer(horizontal: horizontal)
                }
                .background(.white)
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedInput = nil }
                }
            }
            .confirmationDialog("Discard your unsaved draft?",
                                isPresented: $askDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) {
                    draft = PipoPlanV2Draft(original: original)
                    onClose()
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your recorded savings, XP, badges and history remain unchanged.")
            }
            .accessibilityIdentifier("pipo.plan.v2.sheet")
        }
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: navigateBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PipoTheme.cardMuted)
            .accessibilityIdentifier("pipo.plan.v2.back")
            Spacer()
            Text("Manage plan")
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.cardInk)
                .accessibilityIdentifier("pipo.plan.v2.title")
            Spacer()
            Color.clear.frame(width: 48, height: 44)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .overview: overview
        case .target: targetEditor
        case .breakdown: breakdownEditor
        case .date: dateEditor
        case .rhythm: rhythmEditor
        case .impact: impactPreview
        case .review: draftReview
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("ALREADY RECORDED")
                        Text(money(original.recorded))
                            .font(.title3.bold())
                            .foregroundStyle(PipoTheme.cardInk)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    Text(progressText)
                        .font(.headline.bold())
                        .foregroundStyle(PipoTheme.cardAccentReadable)
                        .accessibilityIdentifier("pipo.plan.v2.progress")
                }
                ProgressView(value: progress)
                    .tint(PipoTheme.pink)
                    .accessibilityLabel("Manually recorded progress")
                    .accessibilityValue(progressText)
                Text("Past savings and earned badges are preserved.")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.cardMuted)
            }
            .accessibilityIdentifier("pipo.plan.v2.recorded")
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("ADJUST YOUR GOAL")
                choiceRow("Target & breakdown",
                          detail: money(original.target) + (original.budget.isEmpty ? "" : " · Trip budget"),
                          id: "pipo.plan.v2.editTarget") {
                    step = .target
                }
                Divider().background(PipoTheme.cardBorder)
                choiceRow("Finish date", detail: dateLabel(original.targetDate),
                          id: "pipo.plan.v2.editDate") {
                    step = .date
                }
                sectionTitle("HOW YOU SAVE")
                    .padding(.top, 16)
                choiceRow("Saving approach", detail: rhythmText(original.rhythm, day: original.preferredDay),
                          id: "pipo.plan.v2.editRhythm") {
                    step = .rhythm
                }
            }
            Text(draft.isDirty ? "You have a draft to review." : "Nothing is changed until you review.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }
        .accessibilityIdentifier("pipo.plan.v2.overview")
    }

    private var progress: Double {
        guard original.target > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: original.recorded / original.target).doubleValue))
    }
    private var progressText: String { "\(Int((progress * 100).rounded()))%" }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.bold))
            .foregroundStyle(PipoTheme.cardMuted)
            .accessibilityAddTraits(.isHeader)
    }

    private func choiceRow(_ title: String, detail: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(PipoTheme.cardInk)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.cardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.cardMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open focused editor")
        .accessibilityIdentifier(id)
    }

    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionTitle("TARGET AMOUNT · " + currency)
            TextField("Target amount", text: $draft.targetInput)
                .keyboardType(PipoPlanV2Money.fractionDigits(for: currency) == 0 ? .numberPad : .decimalPad)
                .font(.title3.bold())
                .padding(14)
                .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                .focused($focusedInput, equals: "target")
                .accessibilityIdentifier("pipo.plan.v2.targetAmount")
            Text("Current goal · " + money(original.target))
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
            if let target = draft.target {
                comparison("GOAL TARGET", current: money(original.target), proposed: money(target))
            }
            if !draft.budget.isEmpty {
                if let total = draft.allocationTotal, let target = draft.target,
                   total != target {
                    warning("Your breakdown needs attention",
                            detail: "Items total " + money(total) + ". " +
                            (draft.validationError ?? "Review allocations."))
                } else if draft.allocationTotal == nil {
                    warning("Check your breakdown", detail: "All categories need valid amounts.")
                }
                choiceRow("Adjust trip budget", detail: "Review items and allocation",
                          id: "pipo.plan.v2.editBudget") {
                    step = .breakdown
                }
            } else {
                choiceRow("Add budget categories", detail: "Optional goal allocation",
                          id: "pipo.plan.v2.editBudget") {
                    step = .breakdown
                }
            }
            if let error = draft.validationError, error.contains("target") ||
                error.contains("amount") || error.contains("Allocate") ||
                error.contains("budget") {
                errorText(error)
            }
            Text("Changing a plan doesn't add money.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }
        .accessibilityIdentifier("pipo.plan.v2.targetEditor")
    }

    private var breakdownEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("YOUR BUDGET CATEGORIES")
            ForEach($draft.budget) { $row in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Category name", text: $row.title)
                        .textInputAutocapitalization(.words)
                        .font(.subheadline.bold())
                        .focused($focusedInput, equals: row.id.uuidString + ".name")
                        .accessibilityIdentifier("pipo.plan.v2.budgetName." + row.id.uuidString)
                    TextField("Amount · " + currency, text: $row.input)
                        .keyboardType(PipoPlanV2Money.fractionDigits(for: currency) == 0 ? .numberPad : .decimalPad)
                        .focused($focusedInput, equals: row.id.uuidString + ".amount")
                        .accessibilityIdentifier("pipo.plan.v2.budgetAmount." + row.id.uuidString)
                    Button("Remove " + row.title) {
                        draft.budget.removeAll { $0.id == row.id }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PipoTheme.cardAccentReadable)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            }
            Button {
                draft.budget.append(PipoPlanV2Budget(id: UUID(), title: "", input: ""))
            } label: {
                Label("Add a category", systemImage: "plus.circle")
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
            }
            .foregroundStyle(PipoTheme.cardAccentReadable)
            .accessibilityIdentifier("pipo.plan.v2.addBudget")
            if let total = draft.allocationTotal {
                comparison("ITEM ALLOCATION", current: money(original.target), proposed: money(total))
            }
            if let error = draft.validationError { errorText(error) }
            Text("Categories describe your goal. They do not represent money held by Pipo.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }
        .accessibilityIdentifier("pipo.plan.v2.budgetEditor")
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("PREFERRED FINISH DATE")
            DatePicker("Finish date", selection: $draft.finishDate,
                       in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .frame(minHeight: 50)
                .accessibilityIdentifier("pipo.plan.v2.finishDate")
            Text("Previously · " + dateLabel(original.targetDate))
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
            comparison("GOAL DATE", current: dateLabel(original.targetDate),
                       proposed: dateLabel(draft.finishDate))
            warning("Your amount stays the same",
                    detail: "The recorded total remains " + money(original.recorded) +
                    ". Only future timing changes.")
            if let error = draft.validationError { errorText(error) }
            Text("Changing a plan doesn't add money.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }
        .accessibilityIdentifier("pipo.plan.v2.dateEditor")
    }

    private var rhythmEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(selectableRhythms, id: \.self) { rhythm in
                Button {
                    draft.rhythm = rhythm
                    if rhythm == .weekly || rhythm == .biWeekly {
                        if draft.preferredDay == nil || !(1...7).contains(draft.preferredDay!) {
                            draft.preferredDay = Calendar.current.component(.weekday, from: .now)
                        }
                    } else if rhythm == .monthly {
                        draft.preferredDay = Calendar.current.component(.day, from: .now)
                    } else {
                        draft.preferredDay = nil
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: draft.rhythm == rhythm ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(draft.rhythm == rhythm
                                ? PipoTheme.cardAccentReadable : PipoTheme.cardBorder)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rhythm.title)
                                .font(.headline)
                                .foregroundStyle(PipoTheme.cardInk)
                            Text(rhythm == .flexible ? "Record whenever you choose. No streak pressure." :
                                    rhythm == .monthly ? "Choose a calendar date." :
                                    "Plan future saving reminders.")
                                .font(.footnote)
                                .foregroundStyle(PipoTheme.cardMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(13)
                    .frame(minHeight: 76, alignment: .leading)
                    .background(draft.rhythm == rhythm ? PipoTheme.palePink : .white,
                                in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(draft.rhythm == rhythm
                                ? PipoTheme.cardAccentReadable : PipoTheme.cardBorder)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rhythm.title + (draft.rhythm == rhythm ? ", selected" : ""))
                .accessibilityIdentifier("pipo.plan.v2.rhythm." + rhythm.rawValue)
            }
            if draft.rhythm == .weekly || draft.rhythm == .biWeekly {
                sectionTitle("PREFERRED WEEKDAY")
                Picker("Preferred weekday", selection: $draft.preferredDay) {
                    ForEach(1...7, id: \.self) { index in
                        Text(Calendar.current.weekdaySymbols[index - 1]).tag(Optional(index))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pipo.plan.v2.weekday")
            } else if draft.rhythm == .monthly {
                sectionTitle("PREFERRED CALENDAR DATE")
                Picker("Preferred day", selection: $draft.preferredDay) {
                    ForEach(1...31, id: \.self) { index in
                        Text(String(index)).tag(Optional(index))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pipo.plan.v2.monthDay")
            } else if draft.rhythm == .flexible {
                warning("What changes",
                        detail: "Scheduled suggestions stop. Progress still comes from manual records.")
            }
            if let error = draft.validationError { errorText(error) }
            Text("Previous XP and saving history stay earned.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }
        .accessibilityIdentifier("pipo.plan.v2.rhythmEditor")
    }

    private var selectableRhythms: [SavingRhythm] {
        let standard: [SavingRhythm] = [.weekly, .monthly, .flexible]
        return standard.contains(original.rhythm) ? standard :
            [original.rhythm] + standard
    }

    private var impactPreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let target = draft.target, target != original.target {
                comparison("GOAL TARGET", current: money(original.target), proposed: money(target))
            }
            if let remaining = draft.remaining {
                comparison("STILL TO RECORD",
                           current: money(max(original.target - original.recorded, 0)),
                           proposed: money(remaining))
            }
            if !Calendar.current.isDate(draft.finishDate, inSameDayAs: original.targetDate) {
                comparison("FINISH DATE", current: dateLabel(original.targetDate),
                           proposed: dateLabel(draft.finishDate))
            }
            if draft.rhythm != original.rhythm ||
                (draft.rhythm != .flexible && draft.preferredDay != original.preferredDay) {
                comparison("SAVING APPROACH",
                           current: rhythmText(original.rhythm, day: original.preferredDay),
                           proposed: rhythmText(draft.rhythm, day: draft.preferredDay))
            }
            if draft.rhythm == .flexible {
                comparison("FUTURE SUGGESTIONS",
                           current: suggestionText(draft.priorSuggestion()),
                           proposed: "No fixed schedule")
            } else {
                comparison("SUGGESTED NEXT SAVE",
                           current: suggestionText(draft.priorSuggestion()),
                           proposed: suggestionText(draft.suggested()))
            }
            if !draft.budget.isEmpty && draft.budget != original.budget {
                comparison("BUDGET ALLOCATION", current: money(original.target),
                           proposed: money(draft.allocationTotal ?? 0))
            }
            warning("Plans can change. Your saved steps stay.",
                    detail: "These are suggestions only. No bank transfer or past record changes.")
        }
        .accessibilityIdentifier("pipo.plan.v2.impact")
    }

    private var draftReview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let target = draft.target {
                comparison("TARGET", current: money(original.target), proposed: money(target))
            }
            comparison("SAVING RHYTHM",
                       current: rhythmText(original.rhythm, day: original.preferredDay),
                       proposed: rhythmText(draft.rhythm, day: draft.preferredDay))
            comparison("FINISH DATE", current: dateLabel(original.targetDate),
                       proposed: dateLabel(draft.finishDate))
            comparison("SUGGESTED NEXT SAVE",
                       current: suggestionText(draft.priorSuggestion()),
                       proposed: suggestionText(draft.suggested()))
            warning("What stays unchanged",
                    detail: money(original.recorded) +
                    " in manual saving records · XP · badges · milestones · past history")
            Text("The original plan remains active. This is a draft only.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
                .accessibilityIdentifier("pipo.plan.v2.unsavedNotice")
        }
        .accessibilityIdentifier("pipo.plan.v2.review")
    }

    private func suggestionText(_ amount: Decimal?) -> String {
        amount.map(money) ?? "No fixed schedule"
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func rhythmText(_ rhythm: SavingRhythm, day: Int?) -> String {
        rhythm == .flexible ? "Flexible · no schedule" :
            PersonalPlanFormatting.rhythmLabel(rhythm, day: day)
    }

    private func comparison(_ title: String, current: String, proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(title)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle("CURRENT")
                    Text(current)
                        .font(.subheadline.bold())
                        .foregroundStyle(PipoTheme.cardInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle("PROPOSED")
                    Text(proposed)
                        .font(.subheadline.bold())
                        .foregroundStyle(PipoTheme.cardInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + ". Current " + current + ". Proposed " + proposed)
    }

    private func warning(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.cardInk)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func errorText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(PipoTheme.cardAccentReadable)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pipo.plan.v2.validation")
    }

    private func footer(horizontal: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step == .review
                 ? "Prototype only · No changes saved"
                 : "Preview only · Changes are not saved")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
            Button(action: continueForward) {
                Text(actionLabel)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(actionAllowed ? .white : PipoTheme.cardMuted)
                    .background(actionAllowed ? PipoTheme.pink : PipoTheme.cream,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!actionAllowed)
            .accessibilityIdentifier("pipo.plan.v2.primary")
            .accessibilityHint(step == .review
                ? "Secure saving isn't enabled. Your draft will not be recorded."
                : "Preview-only navigation. No saved records will change.")
        }
        .padding(.horizontal, horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .overlay(alignment: .top) {
            Rectangle().fill(PipoTheme.cardBorder).frame(height: 1)
        }
    }

    private var actionAllowed: Bool {
        switch step {
        case .overview: return false
        case .target, .breakdown, .date, .rhythm: return canPreview
        case .impact: return canPreview
        case .review: return false
        }
    }

    private var actionLabel: String {
        switch step {
        case .overview: "Select an edit above"
        case .target: "Preview target change"
        case .breakdown: "Preview balanced plan"
        case .date: "Preview date impact"
        case .rhythm: draft.rhythm == .flexible ? "Preview Flexible" : "Preview rhythm"
        case .impact: "Review draft plan"
        case .review: "Saving unavailable · Preview"
        }
    }

    private func continueForward() {
        guard actionAllowed else { return }
        focusedInput = nil
        switch step {
        case .target, .breakdown, .date, .rhythm:
            returnEditor = step
            step = .impact
        case .impact:
            step = .review
        default: break
        }
    }

    private func navigateBack() {
        focusedInput = nil
        switch step {
        case .overview:
            if draft.isDirty { askDiscard = true } else { onClose() }
        case .target, .breakdown, .date, .rhythm:
            step = .overview // Preserve unsaved draft on back.
        case .impact:
            step = returnEditor
        case .review:
            step = .impact
        }
    }
}
