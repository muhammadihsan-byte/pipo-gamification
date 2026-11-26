import Lottie
import SwiftUI

enum PersonalPlanStep: Int, CaseIterable, Identifiable {
    case goal = 1
    case target
    case timeline
    case rhythm
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .goal: "Goal"
        case .target: "Target"
        case .timeline: "Timeline"
        case .rhythm: "Saving rhythm"
        case .review: "Review and start"
        }
    }

    var artwork: String {
        switch self {
        case .goal: "MoneyBag"
        case .target: "Calculator"
        case .timeline: "Calendar"
        case .rhythm: "TargetHeart"
        case .review: "StartLine"
        }
    }
}

enum PersonalPlanStyle {
    static let ink = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)
    static let muted = Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)
    static let surface = Color(red: 245 / 255, green: 247 / 255, blue: 249 / 255)
    static let border = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
    static let pink = PipoTheme.approvedActionPink
    static let blush = Color(red: 1, green: 241 / 255, blue: 244 / 255)
    static let berry = Color(red: 176 / 255, green: 40 / 255, blue: 75 / 255)
    static let buttonEdge = Color(red: 205 / 255, green: 56 / 255, blue: 72 / 255)
    static let green = Color(red: 0, green: 108 / 255, blue: 73 / 255)
    static let mint = Color(red: 236 / 255, green: 253 / 255, blue: 245 / 255)
    static let warning = Color(red: 1, green: 244 / 255, blue: 232 / 255)
    static let error = Color(red: 0.76, green: 0.04, blue: 0.13)
}

struct PersonalPlanPage<Content: View, Footer: View>: View {
    var step: PersonalPlanStep
    var onBack: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        SavingPlanPage(flowTitle: "Personal saving plan", stepNumber: step.rawValue,
                       count: PersonalPlanStep.allCases.count, stepTitle: step.title,
                       onBack: onBack, content: content, footer: footer)
    }
}

struct SavingPlanPage<Content: View, Footer: View>: View {
    let flowTitle: String
    let stepNumber: Int
    let count: Int
    let stepTitle: String
    var ready = false
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer()
                .padding(.horizontal, 24)
                .padding(.top, 15)
                .padding(.bottom, 10)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(.white)
                .overlay(alignment: .top) {
                    Rectangle().fill(PersonalPlanStyle.border).frame(height: 1)
                }
        }
        .foregroundStyle(PersonalPlanStyle.ink)
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .tint(PersonalPlanStyle.pink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PipoQuietButtonStyle())
                .accessibilityLabel("Back")

                Text(flowTitle)
                    .font(.subheadline.bold())
                Spacer(minLength: 8)
                Text(ready ? "Ready" : "\(stepNumber) of \(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PersonalPlanStyle.muted)
                    .accessibilityLabel(ready ? "Ready" : "Step \(stepNumber) of \(count)")
            }

            HStack(spacing: count == 7 ? 14 : 6) {
                ForEach(1..<(count + 1), id: \.self) { bar in
                    Capsule()
                        .fill(progressColor(for: bar))
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
            .opacity(ready ? 0 : 1)

            Text(stepTitle)
                .font(.caption.bold())
                .foregroundStyle(PersonalPlanStyle.muted)
        }
    }

    private func progressColor(for bar: Int) -> Color {
        if bar == stepNumber { return PersonalPlanStyle.pink }
        if bar < stepNumber { return PersonalPlanStyle.green }
        return PersonalPlanStyle.border
    }
}

struct PersonalPlanIntro: View {
    let step: PersonalPlanStep
    let title: String
    let subtitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        if step == .review {
            VStack(spacing: 12) {
                illustration(size: 126)
                copy
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 16) {
                illustration(size: 84)
                copy
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var copy: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(PersonalPlanStyle.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func illustration(size: CGFloat) -> some View {
        Group {
            if let animation = LottieAnimation.named(step.artwork, subdirectory: "PersonalPlanMotion") {
                LottieView(animation: animation)
                    .resizable()
                    .playbackMode(reduceMotion || !visible || scenePhase != .active ? .paused(at: .progress(0)) : .playing(
                        .fromProgress(0, toProgress: 1, loopMode: .playOnce)
                    ))
                    .id(step)
            } else if step == .rhythm {
                Image("PlanTargetHeart").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: step == .goal ? 92 : size)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

struct PersonalPlanActions: View {
    var back: () -> Void
    var showsBack = true
    var title = "Continue"
    var dimmed = false
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsBack {
                Button(action: back) {
                    Text("Back")
                    .font(.subheadline.bold())
                    .foregroundStyle(PersonalPlanStyle.muted)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 48)
                    .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PipoQuietButtonStyle())
            }
            Button(title, action: action)
                .buttonStyle(PersonalPlanPrimaryStyle(dimmed: dimmed))
                .disabled(dimmed)
        }
    }
}

struct PersonalPlanPrimaryStyle: ButtonStyle {
    var dimmed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(PipoTheme.primaryActionText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                dimmed ? PersonalPlanStyle.muted
                    : configuration.isPressed ? PipoTheme.deepPink : PersonalPlanStyle.pink,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .pipoPressFeedback(configuration.isPressed, depth: dimmed ? 1 : 3, scale: 1)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12)
                shape.fill(PersonalPlanStyle.berry)
                    .offset(y: 4)
                    .opacity(dimmed ? 0 : 1)
            }
            .padding(.bottom, 4)
    }
}

struct PersonalPlanFieldLabel: View {
    var title: String
    var status: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.caption.bold())
            Spacer()
            if let status {
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PersonalPlanStyle.muted)
            }
        }
    }
}

struct PersonalPlanNote: View {
    let title: String
    let message: String
    var background = PersonalPlanStyle.blush
    var accent = PersonalPlanStyle.berry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(accent)
            Text(message)
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PersonalPlanChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(selected ? PersonalPlanStyle.pink : .white)
                    .overlay {
                        Circle().strokeBorder(
                            selected ? PersonalPlanStyle.pink : PersonalPlanStyle.muted.opacity(0.65)
                        )
                    }
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.caption.bold())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? PersonalPlanStyle.berry : PersonalPlanStyle.ink)
            .personalPlanField(height: 44, selected: selected)
        }
        .buttonStyle(PipoQuietButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    func personalPlanField(height: CGFloat = 48, selected: Bool = false, invalid: Bool = false) -> some View {
        padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background(
                selected ? PersonalPlanStyle.blush : PersonalPlanStyle.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        invalid ? PersonalPlanStyle.error
                            : selected ? PersonalPlanStyle.pink : PersonalPlanStyle.border,
                        lineWidth: invalid ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .pipoAnimate(selected)
    }
}

struct RupiahInput: View {
    let label: String
    @Binding var text: String
    var placeholder = "0"

    var body: some View {
        HStack {
            Text("Rp")
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .accessibilityLabel(label)
                .formatRupiahOnBlur($text)
        }
        .font(.subheadline)
        .personalPlanField(invalid: !text.isEmpty && PersonalPlanFormatting.parseRupiah(text) == nil)
    }
}

private struct RupiahFormatOnBlur: ViewModifier {
    @Binding var text: String
    @FocusState private var editing: Bool

    func body(content: Content) -> some View {
        content.focused($editing).onChange(of: editing) { _, focused in
            if !focused, let amount = PersonalPlanFormatting.parseRupiah(text) {
                text = PersonalPlanFormatting.digits(amount)
            }
        }
    }
}

extension View {
    func formatRupiahOnBlur(_ text: Binding<String>) -> some View {
        modifier(RupiahFormatOnBlur(text: text))
    }
}

struct SavingDayGrid: View {
    let title: String
    let days: [Int]
    @Binding var selection: Int
    let label: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 68), spacing: 4)], spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let selected = selection == day
                    Button {
                        selection = day
                    } label: {
                        Text(label(day))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selected ? .white : PersonalPlanStyle.ink)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selected ? PersonalPlanStyle.pink : PersonalPlanStyle.surface,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(PipoQuietButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

struct SavingDateEditor: View {
    @Binding var entry: SavingDateEntry
    let start: Date
    let calendar: Calendar
    @State private var pickerDate: Date

    init(entry: Binding<SavingDateEntry>, start: Date, calendar: Calendar) {
        _entry = entry
        self.start = start
        self.calendar = calendar
        let initialDate = entry.wrappedValue.date(in: calendar) ?? start
        _pickerDate = State(initialValue: initialDate > start ? initialDate
                             : calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                field("Day", $entry.day)
                field("Month", $entry.month)
                field("Year", $entry.year)
            }
            SavingInlineCalendar(selection: $pickerDate, minimumDate: minimumPickerDate,
                                 calendar: calendar)
                .onChange(of: pickerDate) { _, date in select(date) }
        }
        .onChange(of: entry.day) { _, _ in syncPickerDate() }
        .onChange(of: entry.month) { _, _ in syncPickerDate() }
        .onChange(of: entry.year) { _, _ in syncPickerDate() }
    }

    private func select(_ date: Date) { entry = SavingDateEntry(date, calendar: calendar) }

    private var minimumPickerDate: Date {
        calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    private func syncPickerDate() {
        if let date = entry.date(in: calendar), date > start {
            pickerDate = date
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(PersonalPlanStyle.muted)
            TextField(title, text: text).accessibilityLabel(title).keyboardType(.numberPad)
                .font(.caption.weight(.medium)).personalPlanField(height: 44)
        }
    }
}
