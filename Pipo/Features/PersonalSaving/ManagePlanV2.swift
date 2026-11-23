import Foundation
import SwiftUI

// Manage Plan V2 Option B — a local, unsaved plan draft. No SwiftData writes,
// Supabase mutations, XP awards, or bank operations are allowed in this file.
enum PipoPlanV2Money {
    static let maximum = Decimal(9_007_199_254_740_991)

    static func fractionDigits(for currency: String) -> Int {
        // NumberFormatter.maximumFractionDigits defaults to 2 on several
        // platforms even after currencyCode is set. Use explicit ISO 4217
        // minor units for non-two-decimal currencies; existing IDR plans
        // were created with whole-rupiah inputs and remain whole IDR.
        switch currency.uppercased() {
        case "IDR", "JPY", "KRW", "VND", "CLP", "PYG", "ISK", "BIF",
             "DJF", "GNF", "KMF", "RWF", "UGX", "VUV", "XAF", "XOF", "XPF":
            return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        case "CLF", "UYW":
            return 4
        default:
            return 2
        }
    }

    static func locale(for currency: String) -> Locale {
        // Locale controls separators and display. The goal's ISO code
        // controls units and precision. IDR is not inherently id_ID.
        Locale.current
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

    static func editable(_ value: Decimal, currency: String,
                         locale: Locale? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale ?? self.locale(for: currency)
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits(for: currency)
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
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
        target = goal.exactTargetMinor.map {
            PipoGoalCurrency.decimal($0, code: goal.effectiveCurrencyCode)
        } ?? 0
        recorded = goal.exactRecordedMinor.map {
            PipoGoalCurrency.decimal($0, code: goal.effectiveCurrencyCode)
        } ?? 0
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
        currency = goal.effectiveCurrencyCode
        budget = goal.subItems.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map {
                PipoPlanV2Budget(
                    id: $0.id, title: $0.title,
                    input: PipoPlanV2Money.editable(
                        PipoGoalCurrency.decimal(
                            $0.amountMinorUnits ?? PipoGoalCurrency.legacyMinor(
                                $0.amount, code: goal.effectiveCurrencyCode
                            ) ?? 0,
                            code: goal.effectiveCurrencyCode
                        ), currency: goal.effectiveCurrencyCode
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
            zip(left, right).contains { pair in
                pair.0.0 != pair.1.0 || pair.0.1 != pair.1.1
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(original: PipoPlanV2Original, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _draft = State(initialValue: PipoPlanV2Draft(original: original))
    }

    init(goal: PersonalGoal, onClose: @escaping () -> Void) {
        self.init(original: PipoPlanV2Original(goal: goal), onClose: onClose)
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
        case .rhythm: draft.rhythm == .flexible
            ? "No scheduled dates or streaks."
            : "Updates begin next saving period."
        case .impact: "Take a look before deciding."
        case .review: "A secure save isn't available yet."
        }
    }

    private var canPreview: Bool { draft.isDirty && draft.validationError == nil }

    var body: some View {
        // Measure the hosting viewport before constructing NavigationStack.
        // The previous inner GeometryReader inherited an inflated vertical
        // region from the navigation container in a constrained 320pt host.
        GeometryReader { geometry in
            let horizontal: CGFloat = geometry.size.width <= 350 ? 16 : 20
            NavigationStack {
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, horizontal)
                    // A bounded VStack gives the scroll view exactly the
                    // space remaining after the header and its *actual*
                    // dynamic-height footer, including accessibility text.
                    // A safeAreaInset on the nested ScrollView pushed the
                    // footer beyond the 320pt snapshot host's lower edge.
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
                            Text(step == .review
                                 ? "Prototype only · No changes saved"
                                 : "Preview only · Changes are not saved")
                                .font(.footnote)
                                .foregroundStyle(PipoTheme.cardMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            if step != .review && step != .overview {
                                Text("Nothing changes in your saved records until a secure save is available.")
                                    .font(.footnote)
                                    .foregroundStyle(PipoTheme.cardMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, horizontal)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollBounceBehavior(.basedOnSize)
                    footer(horizontal: horizontal)
                        .padding(.bottom, 12)
                        .background(.white)
                }
                // The measured outer host sets both dimensions; the scroll
                // region yields to the intrinsic dynamic-height footer.
                .frame(width: geometry.size.width,
                       height: geometry.size.height, alignment: .top)
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
            .frame(width: geometry.size.width,
                   height: geometry.size.height, alignment: .top)
            .onAppear {
                #if DEBUG
                if horizontal <= 16 {
                    let host = geometry.frame(in: .global)
                    print("PIPO_320_HOST originY=\(host.minY) sizeH=\(geometry.size.height) " +
                          "safeTop=\(geometry.safeAreaInsets.top) safeBottom=\(geometry.safeAreaInsets.bottom)")
                }
                #endif
            }
        }
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: navigateBack) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        // At AX3/320pt, "Back" previously split into "Bac/k".
                        // Keep the full accessible label on an icon-only
                        // 48pt+ hit target; never truncate the VoiceOver name.
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    } else {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 58, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Apply hit-area geometry to the Button itself, not just its
            // inner Label. XCTest measured the old plain Button at only 30pt.
            .frame(minWidth: 58, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundStyle(PipoTheme.cardMuted)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("pipo.plan.v2.back")
            Spacer(minLength: 4)
            Text("Manage plan")
                .font(.subheadline.bold())
                .lineLimit(1)
                // Navigation chrome must stay on one line on AX3/320pt.
                // The actual page heading and editors remain fully scalable
                // and scrollable, with no caps on user information.
                .minimumScaleFactor(0.65)
                .layoutPriority(1)
                .foregroundStyle(PipoTheme.cardInk)
                .accessibilityLabel("Manage plan")
                .accessibilityIdentifier("pipo.plan.v2.title")
            Spacer(minLength: 4)
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
                            .font(.title2.bold())
                            .foregroundStyle(PipoTheme.cardInk)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(progressText)
                        .font(.headline.bold())
                        .foregroundStyle(PipoTheme.cardAccentReadable)
                        .accessibilityIdentifier("pipo.plan.v2.progress")
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(PipoTheme.cardAccentReadable)
                    .scaleEffect(x: 1, y: 1.8, anchor: .center)
                    .frame(height: 14)
                    .accessibilityLabel("Manually recorded progress")
                    .accessibilityValue(progressText)
                Text("Past savings and earned badges are preserved.")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.cardMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The progress story is the visual anchor, not another form field.
            // Keep the only progress rail and the existing manual-record semantics.
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(PipoTheme.cardAccentReadable.opacity(0.15), lineWidth: 1)
            }

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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(PipoTheme.cardBorder, lineWidth: 1)
            }
            Text(draft.isDirty ? "You have a draft to review." : "Nothing is changed until you review.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.cardMuted)
        }

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
        // Keep the intrinsic Button trait. Grouping a Button into an
        // accessibilityElement can turn it into an Other element in XCTest.
        .accessibilityLabel(title + ". " + detail)
        .accessibilityHint("Open focused editor")
        .accessibilityIdentifier(id)
    }

    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionTitle("TARGET AMOUNT · " + currency)
            HStack(spacing: 2) {
                Text(currency == "IDR" ? "Rp" : currency)
                    .font(.title3.bold())
                    .foregroundStyle(PipoTheme.cardInk)
                    .accessibilityHidden(true)
                TextField("Target amount", text: $draft.targetInput)
                    .keyboardType(PipoPlanV2Money.fractionDigits(for: currency) == 0 ? .numberPad : .decimalPad)
                    .font(.title3.bold())
                    .focused($focusedInput, equals: "target")
                    .accessibilityLabel("Target amount in " + currency)
                    .accessibilityIdentifier("pipo.plan.v2.targetAmount")
            }
            .padding(14)
            .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 12))
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

    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("PREFERRED FINISH DATE")
            DatePicker("Finish date", selection: $draft.finishDate,
                       in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .frame(minHeight: 50)
                // SwiftUI's compact native picker can expose an empty outer
                // accessibility label under large Dynamic Type. Keep the
                // control itself named without replacing its native behavior.
                .accessibilityLabel("Finish date")
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
                        Image(systemName: draft.rhythm == rhythm ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.rhythm == rhythm
                                ? PipoTheme.cardAccentReadable : PipoTheme.cardBorder)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rhythm.title)
                                .font(.headline)
                                .foregroundStyle(PipoTheme.cardInk)
                            Text(rhythm == .flexible ? "Record whenever you choose. No streak pressure." :
                                    rhythm == .monthly ? "Choose a calendar date." :
                                    "Choose a weekday for future suggestions.")
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

    // Current/proposed values must not collide at 320pt, with long currency
    // formats, or at accessibility text sizes. A horizontal pair is preferred
    // when it really fits; otherwise the same content stacks naturally.
    private func comparison(_ title: String, current: String, proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    comparisonValue("Current", value: current, proposed: false)
                        .fixedSize(horizontal: true, vertical: false)
                    comparisonValue("Proposed", value: proposed, proposed: true)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 8) {
                    comparisonValue("Current", value: current, proposed: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    comparisonValue("Proposed", value: proposed, proposed: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + ". Current " + current + ". Proposed " + proposed)
    }

    private func comparisonValue(_ title: String, value: String, proposed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(proposed ? PipoTheme.cardAccentReadable : PipoTheme.cardMuted)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.cardInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(proposed ? PipoTheme.palePink : PipoTheme.cream,
                    in: RoundedRectangle(cornerRadius: 12))
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
            Button(action: continueForward) {
                Text(actionLabel)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(actionAllowed ? .white : PipoTheme.cardMuted)
                    // Accessible pink: white action text reaches >= 4.5:1 contrast.
                    .background(actionAllowed ? PipoTheme.cardAccentReadable : PipoTheme.cream,
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
        .background {
            #if DEBUG
            GeometryReader { metrics in
                Color.clear.onAppear {
                    if horizontal <= 16 {
                        let r = metrics.frame(in: .global)
                        print("PIPO_320_FOOTER globalY=\(r.origin.y) height=\(r.height) bottom=\(r.maxY)")
                    }
                }
                .onChange(of: metrics.size) { _ in
                    if horizontal <= 16 {
                        let r = metrics.frame(in: .global)
                        print("PIPO_320_FOOTER_UPDATE globalY=\(r.origin.y) height=\(r.height) bottom=\(r.maxY)")
                    }
                }
            }
            #endif
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
