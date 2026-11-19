import Foundation
import SwiftUI

/// A Figma-aligned inline monthly calendar shared by Personal and Group Saving.
/// Selection is non-optional so the Swift 6.1.2 optional-Date IRGen crash is not reintroduced.
struct SavingInlineCalendar: View {
    @Binding var selection: Date
    let minimumDate: Date
    let calendar: Calendar
    @State private var displayedMonth: Date

    private struct DayCell: Identifiable {
        let id: Int
        let day: Int
        let date: Date
    }

    init(selection: Binding<Date>, minimumDate: Date, calendar: Calendar) {
        _selection = selection
        self.minimumDate = minimumDate
        self.calendar = calendar
        let chosen = selection.wrappedValue
        _displayedMonth = State(initialValue: calendar.dateInterval(of: .month, for: chosen)?.start ?? chosen)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                monthButton("chevron.left", label: "Previous month", direction: -1)
                    .disabled(!canGoBack)
                Spacer(minLength: 0)
                Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(calendar.locale ?? .current)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PersonalPlanStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton("chevron.right", label: "Next month", direction: 1)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(["M", "T", "W", "T", "F", "S", "S"][index])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(PersonalPlanStyle.muted)
                                .frame(width: 44, height: 20)
                                .id("weekday-\(index)")
                                .accessibilityHidden(true)
                        }
                        ForEach(dayCells) { cell in
                            if cell.day == 0 {
                                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                            } else {
                                dayButton(cell)
                            }
                        }
                    }
                    // 7 × 44pt day targets + 6 × 4pt spacing = 332pt;
                    // horizontally scroll when the parent cannot display all weekdays.
                    .frame(width: 332)
                    .padding(.horizontal, 4)
                }
                .accessibilityHint("Swipe horizontally to reach other weekdays on smaller screens")
                .accessibilityIdentifier("pipo.qa.calendar.horizontal")
                .onAppear { scrollToSelectedWeekday(using: proxy) }
                .onChange(of: selection) { _, _ in scrollToSelectedWeekday(using: proxy) }
            }
        }
        .padding(.vertical, 14)
        .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: selection) { _, updated in
            displayedMonth = calendar.dateInterval(of: .month, for: updated)?.start ?? updated
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(44), spacing: 4), count: 7)
    }

    private func scrollToSelectedWeekday(using proxy: ScrollViewProxy) {
        let weekday = calendar.component(.weekday, from: selection)
        let mondayFirstIndex = (weekday + 5) % 7
        proxy.scrollTo("weekday-\(mondayFirstIndex)", anchor: .trailing)
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var canGoBack: Bool {
        let earliest = calendar.dateInterval(of: .month, for: minimumDate)?.start ?? minimumDate
        return monthStart > earliest
    }

    private var dayCells: [DayCell] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let days = calendar.range(of: .day, in: .month, for: interval.start) else { return [] }
        // The design starts weeks on Monday, independent of the device's locale.
        let mondayOffset = (calendar.component(.weekday, from: interval.start) + 5) % 7
        var result: [DayCell] = []
        for index in 0..<mondayOffset {
            result.append(DayCell(id: index, day: 0, date: interval.start))
        }
        for day in days {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) {
                result.append(DayCell(id: mondayOffset + day - 1, day: day, date: date))
            }
        }
        return result
    }

    private func monthButton(_ symbol: String, label: String, direction: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: direction, to: monthStart) {
                displayedMonth = next
            }
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(PersonalPlanStyle.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayButton(_ cell: DayCell) -> some View {
        let selected = calendar.isDate(selection, inSameDayAs: cell.date)
        let unavailable = calendar.startOfDay(for: cell.date) < calendar.startOfDay(for: minimumDate)
        return Button {
            selection = cell.date
        } label: {
            Text(String(cell.day))
                .font(.caption.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : PersonalPlanStyle.ink.opacity(unavailable ? 0.35 : 1))
                .frame(width: 44, height: 44)
                .background(selected ? PersonalPlanStyle.pink : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .accessibilityLabel(cell.date.formatted(date: .complete, time: .omitted))
        .accessibilityIdentifier("pipo.qa.calendar.day.\(cell.day)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
