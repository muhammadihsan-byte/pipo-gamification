import Foundation

struct PersonalSavingSchedule: Equatable {
    let firstDate: Date
    let lastDate: Date
    let count: Int
    let amount: Int

    init?(
        targetAmount: Int,
        startDate: Date,
        targetDate: Date,
        rhythm: SavingRhythm,
        preferredDay: Int?,
        calendar: Calendar = .current
    ) {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: targetDate)
        guard targetAmount > 0, start <= end else { return nil }

        let dates: (first: Date, last: Date, count: Int)
        switch rhythm {
        case .flexible:
            return nil
        case .monthly:
            let day = preferredDay ?? calendar.component(.day, from: start)
            guard let monthly = Self.monthlyDates(from: start, to: end, day: day, calendar: calendar) else {
                return nil
            }
            dates = monthly
        case .daily, .weekly, .biWeekly:
            let interval = rhythm == .daily ? 1 : (rhythm == .weekly ? 7 : 14)
            let startingWeekday = calendar.component(.weekday, from: start)
            let selectedWeekday = preferredDay ?? startingWeekday
            guard rhythm == .daily || (1...7).contains(selectedWeekday) else { return nil }
            let offset = rhythm == .daily ? 0 : (selectedWeekday - startingWeekday + 7) % 7
            guard
                let first = calendar.date(byAdding: .day, value: offset, to: start),
                first <= end,
                let days = calendar.dateComponents([.day], from: first, to: end).day,
                let last = calendar.date(byAdding: .day, value: (days / interval) * interval, to: first)
            else {
                return nil
            }
            dates = (first, last, days / interval + 1)
        }

        firstDate = dates.first
        lastDate = dates.last
        count = dates.count
        amount = targetAmount / count + (targetAmount.isMultiple(of: count) ? 0 : 1)
    }

    private static func monthlyDates(
        from start: Date,
        to end: Date,
        day: Int,
        calendar: Calendar
    ) -> (first: Date, last: Date, count: Int)? {
        guard
            (1...31).contains(day),
            var firstMonth = calendar.dateInterval(of: .month, for: start)?.start,
            var lastMonth = calendar.dateInterval(of: .month, for: end)?.start,
            var first = date(inMonth: firstMonth, day: day, calendar: calendar),
            var last = date(inMonth: lastMonth, day: day, calendar: calendar)
        else {
            return nil
        }

        if first < start {
            guard
                let month = calendar.date(byAdding: .month, value: 1, to: firstMonth),
                let date = date(inMonth: month, day: day, calendar: calendar)
            else {
                return nil
            }
            firstMonth = month
            first = date
        }
        if last > end {
            guard
                let month = calendar.date(byAdding: .month, value: -1, to: lastMonth),
                let date = date(inMonth: month, day: day, calendar: calendar)
            else {
                return nil
            }
            lastMonth = month
            last = date
        }

        guard
            first <= last,
            let months = calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month
        else {
            return nil
        }
        return (first, last, months + 1)
    }

    private static func date(inMonth month: Date, day: Int, calendar: Calendar) -> Date? {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return nil }
        return calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: month)
    }
}

enum PersonalPlanFormatting {
    static let dateStyle = Date.FormatStyle.dateTime
        .day().month(.wide).year()
        .locale(Locale(identifier: "en_GB"))

    static func rupiah(_ amount: Int) -> String {
        "Rp" + digits(amount)
    }

    static func digits(_ amount: Int) -> String {
        amount.formatted(.number.locale(Locale(identifier: "id_ID")))
    }

    static func parseRupiah(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = text.hasPrefix("Rp")
            ? String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            : text
        let groups = number.split(separator: ".", omittingEmptySubsequences: false)
        guard
            let first = groups.first,
            groups.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
            groups.count == 1 || ((1...3).contains(first.count) && groups.dropFirst().allSatisfy { $0.count == 3 }),
            let amount = Int(groups.joined()),
            amount > 0,
            Double(exactly: amount) != nil
        else {
            return nil
        }
        return amount
    }

    static func rhythmLabel(_ rhythm: SavingRhythm, day: Int?, calendar: Calendar = .current) -> String {
        switch rhythm {
        case .monthly:
            day.map { "Monthly · on the \(ordinal($0))" } ?? "Monthly"
        case .weekly, .biWeekly:
            day.flatMap { (1...7).contains($0) ? calendar.weekdaySymbols[$0 - 1] : nil }
                .map { "\(rhythm.title) · \($0)" } ?? rhythm.title
        case .daily:
            rhythm.title
        case .flexible:
            "Flexible"
        }
    }

    static func ordinal(_ day: Int) -> String {
        let style = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_GB"))
        let suffix = switch day {
        case 1, 21, 31: "st"
        case 2, 22: "nd"
        case 3, 23: "rd"
        default: "th"
        }
        return day.formatted(style) + suffix
    }
}
