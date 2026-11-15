import SwiftUI

enum SatuSakuTheme {
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
}

@MainActor
struct TicketCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
            }
    }
}

@MainActor
struct TicketSeparator: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            .foregroundStyle(SatuSakuTheme.border)
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
                configuration.isPressed ? SatuSakuTheme.deepPink : SatuSakuTheme.pink,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(SatuSakuTheme.deepPink.opacity(0.8), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

@MainActor
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(SatuSakuTheme.muted)
            .frame(minHeight: 54)
            .padding(.horizontal, 22)
            .background(
                configuration.isPressed ? SatuSakuTheme.cream : .white,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
            }
    }
}
