import SwiftUI

@MainActor
struct OnboardingHeaderView: View {
    let progress: Double
    var mascotBounce = false

    var body: some View {
        HStack(spacing: 12) {
            PipoMascotView(state: .happy)
                .frame(width: 64, height: 64)
                .offset(y: mascotBounce ? -5 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.48), value: mascotBounce)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PIPO")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(PipoTheme.ink)
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PipoTheme.muted)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PipoTheme.border)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [PipoTheme.green, PipoTheme.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

@MainActor
struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(PipoTheme.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(PipoTheme.border, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                SpeechBubbleTail()
                    .fill(.white)
                    .frame(width: 18, height: 12)
                    .overlay {
                        SpeechBubbleTail()
                            .stroke(PipoTheme.border, lineWidth: 1)
                    }
                    .offset(x: 28, y: -9)
            }
            .padding(.top, 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

@MainActor
struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(
                configuration.isPressed ? PipoTheme.deepPink : PipoTheme.pink,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PipoTheme.deepPink.opacity(0.8), lineWidth: 1)
            }
            .shadow(
                color: PipoTheme.deepPink.opacity(configuration.isPressed ? 0.08 : 0.22),
                radius: configuration.isPressed ? 1 : 0,
                y: configuration.isPressed ? 1 : 4
            )
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

@MainActor
struct SelectableOptionCard: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var selected = false
    var dashed = false
    var badge: String?

    var body: some View {
        HStack(spacing: 14) {
            Text(symbol)
                .font(.system(size: 28))
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(selected ? PipoTheme.deepPink : PipoTheme.ink)
                        .multilineTextAlignment(.leading)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PipoTheme.green, in: Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(selected ? PipoTheme.pink : PipoTheme.border)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(
            dashed ? PipoTheme.cream : (selected ? PipoTheme.palePink : .white),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    dashed
                        ? PipoTheme.muted.opacity(0.5)
                        : (selected ? PipoTheme.pink : PipoTheme.border),
                    style: StrokeStyle(lineWidth: selected ? 1.8 : 1, dash: dashed ? [6, 5] : [])
                )
        }
        .shadow(
            color: selected && !dashed ? PipoTheme.ink.opacity(0.07) : .clear,
            radius: 5,
            y: 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 20) {
        OnboardingHeaderView(progress: 0.6)
        SpeechBubbleView(text: "What are you saving for first?")
        SelectableOptionCard(symbol: "✈️", title: "Dream Trip", selected: true)
        Button("CONTINUE") {}
            .buttonStyle(TactileButtonStyle())
    }
    .padding()
    .background(PipoTheme.cream)
}
