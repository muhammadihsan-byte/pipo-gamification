import SwiftUI

enum PipoTheme {
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.22)
    static let green = Color(red: 0.02, green: 0.43, blue: 0.31)
    static let mint = Color(red: 0.88, green: 0.95, blue: 0.89)
    static let cream = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let muted = Color(red: 0.38, green: 0.45, blue: 0.56)
    static let coral = Color(red: 1.00, green: 0.32, blue: 0.48)
    static let pink = Color(red: 1.00, green: 0.32, blue: 0.48)
    static let palePink = Color(red: 1.00, green: 0.94, blue: 0.96)
    static let border = Color(red: 0.86, green: 0.89, blue: 0.93)
    static let deepPink = Color(red: 0.82, green: 0.16, blue: 0.31)

    // Approved card roles, sourced from Pipo Figma DS / 02. Keeping them in
    // the existing theme avoids another competing card color system.
    static let cardInk = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let cardMuted = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    static let cardAccentStrong = Color(red: 229 / 255, green: 69 / 255, blue: 105 / 255)
    static let cardBorder = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
}

enum TicketCardStyle {
    case standard
    case approvedCompact
}

@MainActor
struct TicketCard<Content: View>: View {
    private let style: TicketCardStyle
    private let content: Content

    init(style: TicketCardStyle = .standard, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        let radius: CGFloat = style == .approvedCompact ? 18 : 24
        let horizontal: CGFloat = style == .approvedCompact ? 16 : 20

        return content
            .padding(.horizontal, horizontal)
            .padding(.top, style == .approvedCompact ? 15 : 20)
            .padding(.bottom, style == .approvedCompact ? 13 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(style == .approvedCompact ? PipoTheme.cardBorder : PipoTheme.border, lineWidth: 1)
            }
    }
}

/// Read-only data used by both the plan review and an account-owned goal.
/// Rows never imply a real bank account, a transfer or live group ownership.
struct PipoBudgetLine: Identifiable {
    let id: UUID
    let title: String
    let amount: Double
}

enum PipoBudgetPresentation {
    static func percent(of amount: Double, target: Double) -> Int? {
        guard amount.isFinite, amount >= 0, target.isFinite, target > 0 else { return nil }
        let ratio = amount / target * 100
        guard ratio.isFinite, ratio <= Double(Int.max), ratio >= 0 else { return nil }
        return Int(ratio.rounded())
    }

    static func validTotal(for lines: [PipoBudgetLine]) -> Double? {
        guard lines.allSatisfy({ $0.amount.isFinite && $0.amount >= 0 }) else { return nil }
        let sum = lines.reduce(0.0) { $0 + $1.amount }
        return sum.isFinite ? sum : nil
    }

    static func matchesTarget(total: Double, target: Double) -> Bool {
        total.isFinite && target.isFinite && target > 0 && abs(total - target) < 0.005
    }
}

/// Figma PIPO / CARD / 08: Budget Breakdown — approved B (node 1223:6775).
/// The height grows with actual rows and Dynamic Type instead of clipping at
/// the 230-point design example. No sample figures are hardcoded.
@MainActor
struct PipoBudgetBreakdownCard: View {
    let lines: [PipoBudgetLine]
    let targetAmount: Double
    var onEdit: (() -> Void)? = nil

    var body: some View {
        TicketCard(style: .approvedCompact) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("BUDGET CATEGORIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PipoTheme.cardAccentStrong)
                        .accessibilityAddTraits(.isHeader)

                    Spacer(minLength: 8)
                    if let onEdit {
                        Button("Edit", action: onEdit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PipoTheme.cardAccentStrong)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("pipo.budget.edit")
                            .accessibilityLabel("Edit budget breakdown")
                    }
                }

                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PipoTheme.cardInk)
                            .fixedSize(horizontal: false, vertical: true)

                        let detail: String = {
                            guard line.amount.isFinite, line.amount >= 0 else {
                                return "Amount needs review"
                            }
                            let share = PipoBudgetPresentation.percent(of: line.amount, target: targetAmount)
                            return money(line.amount) + (share.map { " · \\($0)% of goal" } ?? " · Check target")
                        }()
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(PipoTheme.cardMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let total = PipoBudgetPresentation.validTotal(for: lines) {
                    Text("TOTAL " + money(total))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PipoTheme.cardAccentStrong)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pipo.budget.total")

                    if !PipoBudgetPresentation.matchesTarget(total: total, target: targetAmount) {
                        Text("The breakdown total differs from this goal’s target of " + money(targetAmount) + ".")
                            .font(.footnote)
                            .foregroundStyle(PipoTheme.cardMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pipo.budget.mismatch")
                    }
                } else {
                    Text("Review the breakdown amounts before using this plan.")
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.cardMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("pipo.card.budgetBreakdownB")
    }
}

@MainActor
struct TicketSeparator: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            .foregroundStyle(PipoTheme.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

@MainActor
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(
                configuration.isPressed ? PipoTheme.deepPink : PipoTheme.pink,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(PipoTheme.deepPink.opacity(0.8), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

@MainActor
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(PipoTheme.muted)
            .frame(minHeight: 54)
            .padding(.horizontal, 22)
            .background(
                configuration.isPressed ? PipoTheme.cream : .white,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(PipoTheme.border, lineWidth: 1)
            }
    }
}
