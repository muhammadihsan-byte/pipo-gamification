import SwiftUI

struct PersonalGoalPlan {
    let title: String
    let category: GoalCategory
    let targetAmount: Double
    // Exact currency and minor-unit value from validated Create Goal input.
    var currencyCode: String = "IDR"
    var targetMinorUnits: Int64? = nil
    let breakdown: [GoalBreakdownDraft]
    let startDate: Date
    let targetDate: Date
    let rhythm: SavingRhythm
    var customCategory: String? = nil
    var preferredSavingDay: Int? = nil
    var contributionOverride: Int? = nil
    var calendar: Calendar = .current

    var categoryTitle: String { customCategory ?? category.title }

    var schedule: PersonalSavingSchedule? {
        guard let rupiah = targetMinorUnits.flatMap(Int.init(exactly:))
            ?? Int(exactly: targetAmount) else { return nil }
        return PersonalSavingSchedule(
            targetAmount: rupiah,
            startDate: startDate,
            targetDate: targetDate,
            rhythm: rhythm,
            preferredDay: preferredSavingDay, calendar: calendar
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

    private struct ReviewCheckpoint {
        let plan: PersonalGoalPlan
        let timeline: Timeline
        let date: SavingDateEntry
        let months: Int
        let monthDay: Int
        let weekday: Int
        let customCategory: String
        let contribution: String
    }

    @State private var checkpoint: ReviewCheckpoint?
    @State private var step: PersonalPlanStep = .goal
    @State private var isEditingFromReview = false
    @State private var showValidation = false
    @State private var wasEditingName = false
    @State private var showCategoryOptions = false
    @State private var title: String
    @State private var category: GoalCategory
    @State private var customCategory = ""
    @State private var targetAmount = ""
    @State private var currencyCode = PipoGoalCurrency.suggested()
    @State private var showsCurrencyPicker = false
    @State private var currencySearch = ""
    @FocusState private var currencySearchFocused: Bool
    @FocusState private var targetAmountFocused: Bool
    @State private var breakdown: [GoalBreakdownDraft] = []
    @State private var startDate: Date
    @State private var timeline: Timeline = .targetDate
    @State private var dateEntry: SavingDateEntry
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
    private let onLater: (UUID) -> Void
    private let onRecordFirst: (UUID) -> Void

    init(
        onBack: @escaping () -> Void,
        onCreated: @escaping (UUID) -> Void = { _ in },
        onLater: ((UUID) -> Void)? = nil,
        onRecordFirst: ((UUID) -> Void)? = nil,
        initialTitle: String = "",
        initialCategory: GoalCategory = .gadget,
        initialRhythm: SavingRhythm = .monthly
    ) {
        let calendar = Self.planCalendar
        let start = calendar.startOfDay(for: .now)
        let target = calendar.date(byAdding: .month, value: 2, to: start) ?? start
        self.calendar = calendar
        self.onBack = onBack
        self.onCreated = onCreated
        self.onLater = onLater ?? onCreated
        self.onRecordFirst = onRecordFirst ?? onCreated
        _title = State(initialValue: initialTitle)
        _category = State(initialValue: initialCategory)
        _rhythm = State(initialValue: initialRhythm)
        _startDate = State(initialValue: start)
        _dateEntry = State(initialValue: SavingDateEntry(target, calendar: calendar))
        _monthDay = State(initialValue: calendar.component(.day, from: start))
        _weekday = State(initialValue: calendar.component(.weekday, from: start))
    }

    var body: some View {
        if step == .review, let plan {
            ReviewPlanView(plan: plan, onBack: goBack, onEdit: edit,
                           onCreated: onCreated, onLater: onLater,
                           onRecordFirst: onRecordFirst)
        } else {
            editPage
        }
    }

    private var editPage: some View {
        PersonalPlanPage(step: step, onBack: goBack) {
            if step == .rhythm {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your saving rhythm")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PersonalPlanStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose a pace that works in real life.")
                        .font(.subheadline)
                        .foregroundStyle(PersonalPlanStyle.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PersonalPlanIntro(step: step, title: stepHeading, subtitle: stepSubtitle)
            }
            stepFields
        } footer: {
            footerActions
        }
        .id(step)
        .accessibilityHidden(showBreakdownDialog)
        .onChange(of: focusedGoalField) { previous, current in
            if previous == .name && current != .name { wasEditingName = true }
        }
        .overlay { breakdownDialog }
        .sheet(isPresented: $showsCurrencyPicker, onDismiss: {
            // Keep the target editor unblocked after the search sheet closes.
            // Users explicitly tap the amount to open its numeric keyboard.
            currencySearchFocused = false
            currencySearch = ""
            targetAmountFocused = false
        }) { currencyPicker }
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
        VStack(spacing: 5) {
            PersonalPlanActions(
                back: goBack,
                showsBack: step != .goal || isEditingFromReview,
                title: isEditingFromReview && plan != nil ? "Back to review" : "Continue",
                dimmed: !stepIsValid && !(step == .target && breakdownMismatch != nil),
                action: advance
            )
            if step == .rhythm && rhythm == .flexible {
                Text("You can change your rhythm later.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
                    .accessibilityIdentifier("pipo.flex.v2.changeLater")
            }
        }
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

    // A dedicated search field avoids the native .searchable overlay retaining
    // the tap while the search keyboard is visible. Currency rows remain actual
    // 56pt buttons, visible immediately below search even with the keyboard.
    private var filteredCurrencyChoices: [String] {
        PipoGoalCurrency.choices.filter {
            currencySearch.isEmpty || $0.localizedCaseInsensitiveContains(currencySearch)
                || PipoGoalCurrency.currencyName($0).localizedCaseInsensitiveContains(currencySearch)
        }
    }

    private var currencyPicker: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PersonalPlanStyle.muted)
                        .accessibilityHidden(true)
                    TextField("Search code or currency", text: $currencySearch)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($currencySearchFocused)
                        .accessibilityIdentifier("pipo.goal.currency.search")
                        .submitLabel(.search)
                    if !currencySearch.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") {
                            currencySearch = ""
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(PersonalPlanStyle.muted)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCurrencyChoices, id: \.self) { code in
                            Button {
                                // Resign the owned search field first. Never
                                // update a picker while a native search overlay
                                // can intercept the currency row's action.
                                currencySearchFocused = false
                                if currencyCode != code {
                                    currencyCode = code
                                    targetAmount = ""
                                    contributionOverride = ""
                                    breakdown = []
                                    showValidation = false
                                }
                                showsCurrencyPicker = false
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(code)
                                            .font(.headline)
                                            .foregroundStyle(PersonalPlanStyle.ink)
                                        Text(PipoGoalCurrency.currencyName(code))
                                            .font(.subheadline)
                                            .foregroundStyle(PersonalPlanStyle.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 8)
                                    if code == currencyCode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(PipoTheme.cardAccentReadable)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .background(code == currencyCode ? PersonalPlanStyle.blush : PersonalPlanStyle.surface,
                                            in: RoundedRectangle(cornerRadius: 14))
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(code + ", " + PipoGoalCurrency.currencyName(code))
                            .accessibilityAddTraits(code == currencyCode ? .isSelected : [])
                            .accessibilityIdentifier("pipo.goal.currency." + code)
                        }
                        if filteredCurrencyChoices.isEmpty {
                            ContentUnavailableView.search(text: currencySearch)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(.white)
            .navigationTitle("Choose goal currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        currencySearchFocused = false
                        showsCurrencyPicker = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var targetFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                PersonalPlanFieldLabel(title: "Currency for this goal", status: "Required")
                Button {
                    // Reopening the sheet must not reuse an old search term,
                    // otherwise choosing IDR then USD can yield zero matches.
                    currencySearch = ""
                    currencySearchFocused = false
                    targetAmountFocused = false
                    showsCurrencyPicker = true
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currencyCode).font(.headline)
                            Text(PipoGoalCurrency.currencyName(currencyCode))
                                .font(.caption).foregroundStyle(PersonalPlanStyle.muted)
                        }
                        Spacer()
                        Text("Change").font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 54)
                    .background(PersonalPlanStyle.blush,
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(PersonalPlanStyle.border, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pipo.goal.currency.choose")
                Text("Suggested from your device region. This applies only to this goal; no money is converted.")
                    .font(.footnote).foregroundStyle(PersonalPlanStyle.muted)
                PersonalPlanFieldLabel(title: "Target amount", status: "Required")
                HStack(spacing: 3) {
                    Text(currencyCode == "IDR" ? "Rp" : currencyCode)
                    TextField("0", text: $targetAmount)
                        .keyboardType(PipoPlanV2Money.fractionDigits(for: currencyCode) == 0 ? .numberPad : .decimalPad)
                        // The surrounding field capsule is 48pt, but its inner
                        // TextField used to expose a 14.7pt hit rectangle to
                        // XCTest/VoiceOver. Give the actual editable control a
                        // reachable target after dismissing currency search.
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .focused($targetAmountFocused)
                        .accessibilityLabel("Target amount in " + currencyCode)
                        .accessibilityIdentifier("pipo.goal.currency.amount")
                }
                .font(.caption.weight(.medium))
                .personalPlanField(invalid: showValidation && targetRupiah == nil)
                if (showValidation || !targetAmount.isEmpty) && targetRupiah == nil {
                    validationMessage("Enter a positive amount with valid " + currencyCode + " precision.")
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
                        Text("Amount (" + currencyCode + ")")
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
                            .keyboardType(PipoPlanV2Money.fractionDigits(for: currencyCode) == 0 ? .numberPad : .decimalPad)
                            .accessibilityLabel("Amount in " + currencyCode + " for \(item.cleanTitle.isEmpty ? "this item" : item.cleanTitle)")
                            .personalPlanField(height: 44, invalid: (showValidation && parsedItem(item) == nil) || breakdownMismatch != nil)
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

            PersonalPlanChoice(title: timeline == .targetDate ? "Target date · selected" : "Target date",
                               selected: timeline == .targetDate) {
                timeline = .targetDate
            }

            if timeline == .targetDate {
                SavingDateEditor(entry: $dateEntry, start: startDate, calendar: calendar)
            }

            PersonalPlanChoice(title: timeline == .duration ? "Duration · selected" : "Duration",
                               selected: timeline == .duration) {
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
                    Text("Aiming for \(dateLabel(targetDate)). Your date is an aspiration, not a promise — you can change it.")
                        .font(.caption)
                        .foregroundStyle(PersonalPlanStyle.muted)
                }
            } else {
                validationMessage("Enter a valid date after today.")
            }
        }
    }

    private var rhythmFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text("STEP 4 OF 5  /  PERSONAL GOAL")
                    .font(.caption2.bold())
                    .foregroundStyle(PersonalPlanStyle.berry)
                ForEach(SavingRhythm.allCases) { option in
                    rhythmChoice(option)
                }
            }

            if rhythm == .flexible {
                PersonalPlanNote(
                    title: "Flexible is a valid rhythm.",
                    message: "No saving days to miss. Record money you have already set aside whenever you are ready."
                )
                .accessibilityIdentifier("pipo.flex.v2.noSchedule")
                if let targetDate {
                    Text("Your goal date of \(dateLabel(targetDate)) is an aspiration, not a required saving day.")
                        .font(.footnote)
                        .foregroundStyle(PersonalPlanStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        TextField("Optional · " + money(schedule.amount), text: $contributionOverride)
                            .keyboardType(PipoPlanV2Money.fractionDigits(for: currencyCode) == 0 ? .numberPad : .decimalPad)
                            .personalPlanField()
                        if !contributionOverride.isEmpty {
                            Button { contributionOverride = "" } label: {
                                Text("Use suggested amount").frame(minHeight: 44)
                            }
                            if enteredContribution == nil { validationMessage("Enter a positive amount in " + currencyCode + ".") }
                        }
                        Text("Leave this blank to use the suggested amount of \(money(schedule.amount))\(rhythm.unitLabel).")
                            .font(.caption)
                            .foregroundStyle(PersonalPlanStyle.berry)
                    }
                    PersonalPlanNote(
                        title: scheduleTitle(schedule, rhythm: rhythm),
                        message: scheduleDetails(schedule, override: enteredContribution, currencyCode: currencyCode)
                    )
                } else {
                    validationMessage("There’s no saving date before your target. Choose another rhythm, saving day, or target date.")
                }
            }
        }
    }

    private func rhythmChoice(_ option: SavingRhythm) -> some View {
        let selected = rhythm == option
        let subtitle: String = {
            switch option {
            case .daily: "Set a little aside each day."
            case .weekly: "Choose your saving day each week."
            case .biWeekly: "Plan around a 14-day cycle."
            case .monthly: "Pick a date that suits you."
            case .flexible: "Whenever you can. No saving streak."
            }
        }()
        return Button { rhythm = option } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? PersonalPlanStyle.berry : PersonalPlanStyle.muted)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(PersonalPlanStyle.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PersonalPlanStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(selected ? PersonalPlanStyle.blush : .white,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? PersonalPlanStyle.berry : PersonalPlanStyle.border,
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(option.title + ". " + subtitle)
        .accessibilityIdentifier("pipo.flex.v2.rhythm." + option.rawValue)
    }

    private func money(_ minor: Int) -> String {
        PipoGoalCurrency.formatted(Int64(minor), code: currencyCode)
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanCategory: String { customCategory.trimmingCharacters(in: .whitespacesAndNewlines) }
    // Existing variable names remain for surrounding plan UI compatibility;
    // from now on these are currency MINOR units, never assumed rupiah.
    private var targetRupiah: Int? { PipoGoalCurrency.parseMinor(targetAmount, code: currencyCode).flatMap(Int.init(exactly:)) }

    private func parsedItem(_ item: GoalBreakdownDraft) -> Int? {
        PipoGoalCurrency.parseMinor(item.amount, code: currencyCode).flatMap(Int.init(exactly:))
    }

    private var breakdownTotal: Int? {
        guard !breakdown.isEmpty else { return nil }
        var total = 0
        for item in breakdown {
            guard !item.cleanTitle.isEmpty, let minor = parsedItem(item) else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(minor)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
    private var enteredContribution: Int? { PipoGoalCurrency.parseMinor(contributionOverride, code: currencyCode).flatMap(Int.init(exactly:)) }
    private var validRhythm: Bool {
        rhythm == .flexible || (schedule != nil && (contributionOverride.isEmpty || enteredContribution != nil))
    }

    private var breakdownMismatch: (total: Int, target: Int, difference: Int, direction: String)? {
        guard !breakdown.isEmpty, let total = breakdownTotal, let target = targetRupiah, total != target else {
            return nil
        }
        return (total, target, abs(total - target), total > target ? "above" : "below")
    }

    private var targetDate: Date? {
        let date = timeline == .targetDate
            ? dateEntry.date(in: calendar)
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
            title: cleanTitle, category: category,
            targetAmount: NSDecimalNumber(decimal: PipoGoalCurrency.decimal(Int64(targetRupiah), code: currencyCode)).doubleValue,
            currencyCode: currencyCode, targetMinorUnits: Int64(targetRupiah),
            breakdown: breakdown, startDate: startDate, targetDate: targetDate, rhythm: rhythm,
            customCategory: category == .other ? cleanCategory : nil,
            preferredSavingDay: preferredSavingDay,
            contributionOverride: rhythm == .flexible ? nil : enteredContribution, calendar: calendar
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
        case .timeline: "When do you want to achieve it?"
        case .rhythm: "What’s your saving rhythm?"
        case .review: "Review your plan"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .goal: "Hi, I’m Pipo! Let’s give your next goal a little direction."
        case .target: "Set a target amount for \(cleanTitle)."
        case .timeline: "Set a target for \(cleanTitle)."
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
        if isEditingFromReview, let checkpoint {
            if plan == nil { restore(checkpoint) }
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
        if next == .review {
            isEditingFromReview = false
            checkpoint = nil
        }
        step = next
    }

    private func edit(_ field: PersonalPlanStep) {
        guard let plan else { return }
        checkpoint = ReviewCheckpoint(plan: plan, timeline: timeline, date: dateEntry, months: durationMonths,
                                      monthDay: monthDay, weekday: weekday, customCategory: customCategory,
                                      contribution: contributionOverride)
        isEditingFromReview = true
        move(to: field)
    }

    private func restore(_ checkpoint: ReviewCheckpoint) {
        let previous = checkpoint.plan
        title = previous.title
        category = previous.category
        customCategory = checkpoint.customCategory
        currencyCode = previous.currencyCode
        if let minor = previous.targetMinorUnits {
            targetAmount = PipoPlanV2Money.editable(PipoGoalCurrency.decimal(minor, code: currencyCode), currency: currencyCode)
        }
        breakdown = previous.breakdown
        timeline = checkpoint.timeline
        dateEntry = checkpoint.date
        durationMonths = checkpoint.months
        rhythm = previous.rhythm
        monthDay = checkpoint.monthDay
        weekday = checkpoint.weekday
        contributionOverride = checkpoint.contribution
    }

    private static var planCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = .current
        return calendar
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
