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

enum PipoColors {
    static let accentPrimary = Color(red: 255 / 255, green: 101 / 255, blue: 132 / 255)
    static let accentStrong = Color(red: 229 / 255, green: 69 / 255, blue: 105 / 255)
    static let accentSoft = Color(red: 255 / 255, green: 241 / 255, blue: 244 / 255)
    static let accentBorder = Color(red: 254 / 255, green: 205 / 255, blue: 206 / 255)

    static let backgroundBase = Color.white
    static let backgroundSubtle = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
    static let surfaceMuted = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    static let borderDefault = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)

    static let textStrong = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let textPrimary = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)
    static let textSecondary = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    static let textSubtle = Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)
    static let textMuted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
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
