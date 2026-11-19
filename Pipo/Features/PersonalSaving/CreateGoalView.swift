import SwiftUI

struct PersonalGoalPlan {
    let title: String
    let category: GoalCategory
    let targetAmount: Double
    let breakdown: [GoalBreakdownDraft]
    let startDate: Date
    let targetDate: Date
    let rhythm: SavingRhythm
    var customCategory: String? = nil
    var preferredSavingDay: Int? = nil
    var contributionOverride: Int? = nil

    var categoryTitle: String { customCategory ?? category.title }

    var schedule: PersonalSavingSchedule? {
        guard let rupiah = Int(exactly: targetAmount) else { return nil }
        return PersonalSavingSchedule(
            targetAmount: rupiah,
            startDate: startDate,
            targetDate: targetDate,
            rhythm: rhythm,
            preferredDay: preferredSavingDay
        )
    }
}

@MainActor
struct CreateGoalView: View {
    private enum Timeline: String {
        case targetDate = "Target date"
        case duration = "Duration"
    }

    private enum GoalField: Hashable {
        case name
        case customCategory
    }

    @State private var step: PersonalPlanStep = .goal
    @State private var isEditingFromReview = false
    @State private var showValidation = false
    @State private var wasEditingName = false
    @State private var showCategoryOptions = false
    @State private var title: String
    @State private var category: GoalCategory
    @State private var customCategory = ""
    @State private var targetAmount = ""
    @State private var breakdown: [GoalBreakdownDraft] = []
    @State private var startDate: Date
    @State private var timeline: Timeline = .targetDate
    @State private var targetDay: String
    @State private var targetMonth: String
    @State private var targetYear: String
    @State private var calendarMonth: Date
    @State private var durationMonths = 9
    @State private var rhythm: SavingRhythm
    @State private var contributionOverride = ""
    @State private var monthDay: Int
    @State private var weekday: Int
    @State private var showBreakdownDialog = false
    @FocusState private var focusedGoalField: GoalField?

    private let calendar: Calendar
    private let onBack: () -> Void
    private let onCreated: (UUID) -> Void

    init(
        onBack: @escaping () -> Void,
        onCreated: @escaping (UUID) -> Void = { _ in },
        initialTitle: String = "",
        initialCategory: GoalCategory = .gadget,
        initialRhythm: SavingRhythm = .monthly
    ) {
        let calendar = Self.planCalendar
        let start = calendar.startOfDay(for: .now)
        let target = calendar.date(byAdding: .month, value: 2, to: start) ?? start
        let date = calendar.dateComponents([.day, .month, .year], from: target)
        self.calendar = calendar
        self.onBack = onBack
        self.onCreated = onCreated
        _title = State(initialValue: initialTitle)
        _category = State(initialValue: initialCategory)
        _rhythm = State(initialValue: initialRhythm)
        _startDate = State(initialValue: start)
        _targetDay = State(initialValue: String(format: "%02d", date.day ?? 1))
        _targetMonth = State(initialValue: String(format: "%02d", date.month ?? 1))
        _targetYear = State(initialValue: String(date.year ?? 2027))
        _calendarMonth = State(initialValue: target)
        _monthDay = State(initialValue: calendar.component(.day, from: start))
        _weekday = State(initialValue: calendar.component(.weekday, from: start))
    }

    var body: some View {
        if step == .review, let plan {
            ReviewPlanView(plan: plan, onBack: goBack, onEdit: edit, onCreated: onCreated)
        } else {
            editPage
        }
    }

    private var editPage: some View {
        PersonalPlanPage(step: step, onBack: goBack) {
            PersonalPlanIntro(step: step, title: stepHeading, subtitle: stepSubtitle)
            stepFields
        } footer: {
            footerActions
        }
        .id(step)
        .accessibilityHidden(showBreakdownDialog)
        .onChange(of: focusedGoalField) { previous, current in
            if previous == .name && current != .name { wasEditingName = true }
        }
        .onChange(of: enteredTargetDate) { _, date in
            if let date, date > startDate { calendarMonth = date }
        }
        .overlay { breakdownDialog }
    }

    @ViewBuilder
    private var stepFields: some View {
        switch step {
        case .goal: goalFields
        case .target: targetFields
        case .timeline: timelineFields
        case .rhythm: rhythmFields
        case .review: EmptyView()
        }
    }

    private var footerActions: some View {
        PersonalPlanActions(
            back: goBack,
            showsBack: step != .goal || isEditingFromReview,
            title: isEditingFromReview && plan != nil ? "Back to review" : "Continue",
            dimmed: !stepIsValid && !(step == .target && breakdownMismatch != nil),
            action: advance
        )
    }

    @ViewBuilder
    private var breakdownDialog: some View {
        if showBreakdownDialog, let mismatch = breakdownMismatch {
            let explanation = "Your items total \(money(mismatch.total)), \(money(mismatch.difference)) \(mismatch.direction) your target of \(money(mismatch.target))."
            PersonalPlanDialog {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(PersonalPlanStyle.error)
                    .frame(width: 56, height: 56)
                    .background(PersonalPlanStyle.warning, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                Text("Breakdown is \(mismatch.direction) your target")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(explanation + " Adjust the items or the target so the totals match.")
                    .font(.footnote)
                    .foregroundStyle(PersonalPlanStyle.muted)
                Button("Adjust breakdown") { showBreakdownDialog = false }
                    .buttonStyle(PersonalPlanPrimaryStyle())
            }
        }
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(PersonalPlanStyle.error)
    }

    private var goalFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                PersonalPlanFieldLabel(title: "Goal name", status: "Required")
                let invalid = (showValidation || wasEditingName) && cleanTitle.isEmpty
                TextField("Give your goal a name", text: $title)
                    .accessibilityLabel("Goal name")
                    .focused($focusedGoalField, equals: .name)
                    .textInputAutocapitalization(.sentences)
                    .font(.caption.weight(.medium))
                    .personalPlanField(invalid: invalid)
                if invalid {
                    validationMessage("Enter a goal name to continue.")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                PersonalPlanFieldLabel(title: "Goal category", status: "Required")
                Button {
                    focusedGoalField = nil
                    showCategoryOptions.toggle()
                } label: {
                    HStack {
                        Text(category.title).font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: showCategoryOptions ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PersonalPlanStyle.muted)
                    }
                    .personalPlanField()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Goal category")
                .accessibilityValue(category.title)

                if showCategoryOptions {
                    VStack(spacing: 2) {
                        ForEach(GoalCategory.allCases) { option in
                            Button {
                                category = option
                                showCategoryOptions = false
                            } label: {
                                HStack {
                                    Text(option.title)
                                    Spacer()
                                    if option == category {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(option == category ? PersonalPlanStyle.berry : PersonalPlanStyle.ink)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(
                                    option == category ? PersonalPlanStyle.blush : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(option == category ? .isSelected : [])
                        }
                    }
                    .padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PersonalPlanStyle.border) }
                }
            }

            if category == .other {
                VStack(alignment: .leading, spacing: 8) {
                    PersonalPlanFieldLabel(title: "Custom category", status: "Required")
                    TextField("Name your category", text: $customCategory)
                        .accessibilityLabel("Custom category")
                        .focused($focusedGoalField, equals: .customCategory)
                        .textInputAutocapitalization(.sentences)
                        .font(.caption.weight(.medium))
                        .personalPlanField(invalid: showValidation && cleanCategory.isEmpty)
                    if cleanCategory.isEmpty {
                        validationMessage("Enter a category for your goal.")
                    }
                }
            } else {
                PersonalPlanNote(
                    title: "A goal that’s yours",
                    message: "Pick something that matters to you. You can change the plan before you start."
                )
            }
        }
    }

    private var targetFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                PersonalPlanFieldLabel(title: "Target amount", status: "Required")
                HStack(spacing: 3) {
                    Text("Rp")
                    TextField("0", text: $targetAmount)
                        .formatRupiahOnBlur($targetAmount)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Target amount in rupiah")
                }
                .font(.caption.weight(.medium))
                .personalPlanField(invalid: showValidation && targetRupiah == nil)
                if (showValidation || !targetAmount.isEmpty) && targetRupiah == nil {
                    validationMessage("Enter a target greater than Rp0.")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                PersonalPlanFieldLabel(title: "Target breakdown", status: "Optional")
                Text("List what the target covers, or continue without a breakdown.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)

                if !breakdown.isEmpty {
                    HStack {
                        Text("Item")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Amount (Rp)")
                            .frame(width: 105, alignment: .leading)
                        Color.clear.frame(width: 44, height: 1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PersonalPlanStyle.muted)
                }

                ForEach($breakdown) { $item in
                    HStack(spacing: 8) {
                        TextField("Item name", text: $item.title)
                            .accessibilityLabel("Breakdown item name")
                            .personalPlanField(height: 44, invalid: showValidation && item.cleanTitle.isEmpty)
                        TextField("0", text: $item.amount)
                            .formatRupiahOnBlur($item.amount)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Amount in rupiah for \(item.cleanTitle.isEmpty ? "this item" : item.cleanTitle)")
                            .personalPlanField(height: 44, invalid: (showValidation && item.rupiah == nil) || breakdownMismatch != nil)
                            .frame(width: 105)
                        Button {
                            let id = item.id
                            breakdown.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.body.weight(.medium))
                                .foregroundStyle(PersonalPlanStyle.muted)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove breakdown item")
                    }
                    .font(.caption.weight(.medium))
                }

                Button {
                    breakdown.append(GoalBreakdownDraft())
                } label: {
                    Label("Add row", systemImage: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(PersonalPlanStyle.berry)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(PersonalPlanStyle.pink, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                }
                .buttonStyle(.plain)

                if !breakdown.isEmpty, breakdownTotal == nil {
                    validationMessage("Enter a name and a positive amount for every item, or remove the empty rows.")
                }
                if let total = breakdownTotal, !breakdown.isEmpty {
                    breakdownSummary(total: total)
                }
            }
        }
    }

    private func breakdownSummary(total: Int) -> some View {
        let mismatch = breakdownMismatch
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Breakdown total")
                    .font(.caption.bold())
                Spacer()
                Text(money(total))
                    .font(.subheadline.bold())
                    .foregroundStyle(mismatch == nil ? PersonalPlanStyle.green : PersonalPlanStyle.error)
            }
            if let mismatch {
                validationMessage("\(money(mismatch.difference)) \(mismatch.direction) target. Adjust the amounts so the totals match.")
            } else if let targetRupiah {
                Text("Matches your target of \(money(targetRupiah)).")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PersonalPlanStyle.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            mismatch == nil ? PersonalPlanStyle.mint : PersonalPlanStyle.warning,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var timelineFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose one · Required")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)

            PersonalPlanChoice(title: Timeline.targetDate.rawValue, selected: timeline == .targetDate) {
                timeline = .targetDate
            }

            if timeline == .targetDate {
                HStack(spacing: 10) {
                    dateField("Day", text: $targetDay)
                    dateField("Month", text: $targetMonth)
                    dateField("Year", text: $targetYear)
                }
                PersonalPlanCalendar(
                    month: $calendarMonth,
                    selected: enteredTargetDate,
                    minimumDate: startDate,
                    calendar: calendar,
                    onSelect: selectTargetDate
                )
            }

            PersonalPlanChoice(title: Timeline.duration.rawValue, selected: timeline == .duration) {
                timeline = .duration
            }

            if timeline == .duration {
                PersonalPlanFieldLabel(title: "How long?", status: "Required")
                Menu {
                    Picker("Duration", selection: $durationMonths) {
                        ForEach(1...36, id: \.self) { months in
                            Text(durationLabel(months)).tag(months)
                        }
                    }
                } label: {
                    HStack {
                        Text(durationLabel(durationMonths))
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.medium))
                    .personalPlanField()
                }
            }

            if let targetDate {
                if timeline == .duration {
                    PersonalPlanNote(
                        title: "Estimated end date · \(dateLabel(targetDate))",
                        message: "\(durationLabel(durationMonths)) from today, \(dateLabel(startDate)). This is the date you’re aiming for."
                    )
                } else {
                    Text("Your target date is \(dateLabel(targetDate)).")
                        .font(.caption)
                        .foregroundStyle(PersonalPlanStyle.muted)
                }
            } else {
                validationMessage("Enter a valid date after today.")
            }
        }
    }

    private func dateField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PersonalPlanStyle.muted)
            TextField(label, text: text)
                .accessibilityLabel(label)
                .keyboardType(.numberPad)
                .font(.caption.weight(.medium))
                .personalPlanField(height: 42, invalid: showValidation && targetDate == nil)
        }
    }

    private var rhythmFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saving frequency · Required")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
                HStack(spacing: 8) {
                    rhythmChoice(.daily)
                    rhythmChoice(.weekly)
                }
                HStack(spacing: 8) {
                    rhythmChoice(.biWeekly)
                    rhythmChoice(.monthly)
                }
                rhythmChoice(.flexible)
            }

            if rhythm == .flexible {
                PersonalPlanNote(
                    title: "Save at your own pace",
                    message: "Choose when and how much to save. There’s no set saving day or amount."
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text(cleanTitle).font(.subheadline.bold())
                    if let targetRupiah { Text(money(targetRupiah)).font(.title3.bold()) }
                    if let targetDate {
                        Text("You’re aiming for \(dateLabel(targetDate)), without a fixed saving schedule.")
                            .font(.footnote)
                            .foregroundStyle(PersonalPlanStyle.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            } else {
                if rhythm == .monthly {
                    SavingDayGrid(title: "Preferred saving date", days: Array(1...31), selection: $monthDay) { String($0) }
                    Text("For shorter months, Pipo uses the last day of the month.")
                        .font(.caption)
                        .foregroundStyle(PersonalPlanStyle.muted)
                } else if rhythm == .weekly || rhythm == .biWeekly {
                    SavingDayGrid(title: "Preferred saving day", days: [2, 3, 4, 5, 6, 7, 1], selection: $weekday) {
                        calendar.shortWeekdaySymbols[$0 - 1]
                    }
                }

                if let schedule {
                    VStack(alignment: .leading, spacing: 8) {
                        PersonalPlanFieldLabel(title: "Planned contribution")
                        RupiahInput(label: "Planned contribution", text: $contributionOverride,
                                    placeholder: PersonalPlanFormatting.digits(schedule.amount))
                        if !contributionOverride.isEmpty {
                            Button("Use suggested amount") { contributionOverride = "" }
                                .frame(minHeight: 44)
                            if enteredContribution == nil { validationMessage("Enter a positive amount in rupiah.") }
                        }
                        Text("Leave this blank to use the suggested amount of \(money(schedule.amount))\(rhythm.unitLabel).")
                            .font(.caption)
                            .foregroundStyle(PersonalPlanStyle.berry)
                    }
                    PersonalPlanNote(
                        title: scheduleTitle(schedule, rhythm: rhythm),
                        message: scheduleDetails(schedule, override: enteredContribution)
                    )
                } else {
                    validationMessage("There’s no saving date before your target. Choose another rhythm, saving day, or target date.")
                }
            }
        }
    }

    private func rhythmChoice(_ option: SavingRhythm) -> some View {
        PersonalPlanChoice(title: option.title, selected: rhythm == option) { rhythm = option }
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanCategory: String { customCategory.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var targetRupiah: Int? { PersonalPlanFormatting.parseRupiah(targetAmount) }

    private var breakdownTotal: Int? { breakdown.validBreakdownTotal }
    private var enteredContribution: Int? { PersonalPlanFormatting.parseRupiah(contributionOverride) }
    private var validRhythm: Bool {
        rhythm == .flexible || (schedule != nil && (contributionOverride.isEmpty || enteredContribution != nil))
    }

    private var breakdownMismatch: (total: Int, target: Int, difference: Int, direction: String)? {
        guard !breakdown.isEmpty, let total = breakdownTotal, let target = targetRupiah, total != target else {
            return nil
        }
        return (total, target, abs(total - target), total > target ? "above" : "below")
    }

    private var enteredTargetDate: Date? {
        guard
            let day = Int(targetDay), let month = Int(targetMonth), let year = Int(targetYear),
            (1...31).contains(day), (1...12).contains(month), (1...9999).contains(year),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            calendar.component(.day, from: date) == day
        else {
            return nil
        }
        return date
    }

    private var targetDate: Date? {
        let date = timeline == .targetDate
            ? enteredTargetDate
            : calendar.date(byAdding: .month, value: durationMonths, to: startDate)
        guard let date, date > startDate else { return nil }
        return date
    }

    private var preferredSavingDay: Int? {
        switch rhythm {
        case .monthly: monthDay
        case .weekly, .biWeekly: weekday
        case .daily, .flexible: nil
        }
    }

    private var schedule: PersonalSavingSchedule? {
        guard let targetRupiah, let targetDate else { return nil }
        return PersonalSavingSchedule(
            targetAmount: targetRupiah,
            startDate: startDate,
            targetDate: targetDate,
            rhythm: rhythm,
            preferredDay: preferredSavingDay,
            calendar: calendar
        )
    }

    private var plan: PersonalGoalPlan? {
        guard
            !cleanTitle.isEmpty,
            category != .other || !cleanCategory.isEmpty,
            let targetRupiah,
            breakdown.isEmpty || breakdownTotal == targetRupiah,
            let targetDate,
            validRhythm
        else {
            return nil
        }
        return PersonalGoalPlan(
            title: cleanTitle, category: category, targetAmount: Double(targetRupiah),
            breakdown: breakdown, startDate: startDate, targetDate: targetDate, rhythm: rhythm,
            customCategory: category == .other ? cleanCategory : nil,
            preferredSavingDay: preferredSavingDay,
            contributionOverride: rhythm == .flexible ? nil : enteredContribution
        )
    }

    private var stepIsValid: Bool {
        switch step {
        case .goal: !cleanTitle.isEmpty && (category != .other || !cleanCategory.isEmpty)
        case .target: targetRupiah != nil && (breakdown.isEmpty || breakdownTotal == targetRupiah)
        case .timeline: targetDate != nil
        case .rhythm: validRhythm
        case .review: plan != nil
        }
    }

    private var stepHeading: String {
        switch step {
        case .goal: "What are you saving for?"
        case .target: "How much do you need?"
        case .timeline: "When do you want to reach your goal?"
        case .rhythm: "What’s your saving rhythm?"
        case .review: "Review your plan"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .goal: "Hi, I’m Pipo! Let’s give your next goal a little direction."
        case .target: "Set a target amount for \(cleanTitle)."
        case .timeline: "Pick a date or set a timeline for \(cleanTitle)."
        case .rhythm: "Choose how often you want to save for \(cleanTitle)."
        case .review: "Check the details for \(cleanTitle)."
        }
    }

    private func advance() {
        focusedGoalField = nil
        showValidation = true
        guard stepIsValid else {
            if step == .target && breakdownMismatch != nil { showBreakdownDialog = true }
            return
        }
        if isEditingFromReview, plan != nil {
            move(to: .review)
        } else if let next = PersonalPlanStep(rawValue: step.rawValue + 1) {
            move(to: next)
        }
    }

    private func goBack() {
        focusedGoalField = nil
        if isEditingFromReview, plan != nil {
            move(to: .review)
        } else if let previous = PersonalPlanStep(rawValue: step.rawValue - 1) {
            move(to: previous)
        } else {
            onBack()
        }
    }

    private func move(to next: PersonalPlanStep) {
        showValidation = false
        showCategoryOptions = false
        if next == .review { isEditingFromReview = false }
        step = next
    }

    private func edit(_ field: PersonalPlanStep) {
        isEditingFromReview = true
        move(to: field)
    }

    private func selectTargetDate(_ date: Date) {
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = components.day, let month = components.month, let year = components.year else { return }
        targetDay = String(format: "%02d", day)
        targetMonth = String(format: "%02d", month)
        targetYear = String(year)
    }

    private static var planCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = .current
        return calendar
    }
}

struct PersonalPlanCalendar: View {
    @Binding var month: Date
    let selected: Date?
    let minimumDate: Date
    let calendar: Calendar
    let onSelect: (Date) -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                monthButton("chevron.left", label: "Previous month", direction: -1)
                    .disabled(!canStepBack)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(calendar.locale ?? .current)))
                    .font(.subheadline.bold())
                Spacer()
                monthButton("chevron.right", label: "Next month", direction: 1)
            }

            if let interval = calendar.dateInterval(of: .month, for: month),
               let days = calendar.range(of: .day, in: .month, for: interval.start) {
                let leading = (calendar.component(.weekday, from: interval.start) + 5) % 7
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                            .foregroundStyle(PersonalPlanStyle.muted)
                            .accessibilityHidden(true)
                    }
                    ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(days, id: \.self) { day in
                        if let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) {
                            dayButton(day, date: date)
                        }
                    }
                }
                .font(.caption.weight(.medium))
            }
        }
        .padding(12)
        .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var canStepBack: Bool {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return false }
        return start > minimumDate
    }

    private func monthButton(_ symbol: String, label: String, direction: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: direction, to: month) {
                month = next
            }
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(PersonalPlanStyle.muted)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Int, date: Date) -> some View {
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            onSelect(date)
        } label: {
            Text(String(day))
                .foregroundStyle(isSelected ? .white : PersonalPlanStyle.ink.opacity(date <= minimumDate ? 0.4 : 1))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isSelected ? PersonalPlanStyle.pink : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(date <= minimumDate)
        .accessibilityLabel(dateLabel(date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private func durationLabel(_ months: Int) -> String {
    months == 1 ? "1 month" : "\(months) months"
}

#Preview {
    NavigationStack {
        CreateGoalView(onBack: {})
    }
}
