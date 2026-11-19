import SwiftUI

enum OnboardingPipoReaction {
    case acknowledge
    case reassure
    case celebrate

    var lift: CGFloat {
        switch self {
        case .acknowledge: -5
        case .reassure: -3
        case .celebrate: -11
        }
    }

    var rotation: Double {
        switch self {
        case .acknowledge: -4
        case .reassure: 3
        case .celebrate: -7
        }
    }

    var scale: CGFloat {
        switch self {
        case .acknowledge: 1.025
        case .reassure: 1.015
        case .celebrate: 1.07
        }
    }
}

/// Onboarding-only reactions. The canonical V4 SVG and tap gesture remain unmodified.
@MainActor
struct OnboardingPipoView: View {
    let height: CGFloat
    var reaction: OnboardingPipoReaction = .acknowledge
    var reactionID = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PipoMascotView(companion: .idle)
            .frame(width: height * 460 / 500, height: height)
            .phaseAnimator([false, true, false], trigger: reactionID) { content, active in
                content
                    .offset(y: active && !reduceMotion ? reaction.lift : 0)
                    .rotationEffect(.degrees(active && !reduceMotion ? reaction.rotation : 0))
                    .scaleEffect(active && !reduceMotion ? reaction.scale : 1)
            } animation: { active in
                active
                    ? .spring(response: 0.23, dampingFraction: 0.67)
                    : .spring(response: 0.43, dampingFraction: 0.79)
            }
            .frame(maxWidth: .infinity)
    }
}

/// Duolingo-inspired progress structure, styled exclusively with Pipo tokens.
@MainActor
struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PipoTheme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(step == .welcome)
            .opacity(step == .welcome ? 0 : 1)
            .accessibilityIdentifier("pipo.onboarding.back")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PipoTheme.border)
                    Capsule()
                        .fill(PipoTheme.pink)
                        .frame(width: geometry.size.width * step.progress)
                }
            }
            .frame(height: 8)

            Text("\(step.number) / 4")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PipoTheme.muted)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding step \(step.number) of 4")
    }
}

@MainActor
struct OnboardingHeaderView: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            // A small static V4 companion avoids running two animated web views.
            PipoMascotView(companion: .reassurance)
                .frame(width: 58, height: 62)
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

/// The pointer and body share one closed path, so the outline never draws
/// a dividing line through the tail or leaves the triangle floating.
private struct PipoSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 10
        let radius: CGFloat = 20
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY + tailHeight
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        // Aim the tail toward the centered V4 mascot, not the left gutter.
        path.addLine(to: CGPoint(x: rect.midX - 11, y: top))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 11, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + radius),
            control: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: right - radius, y: bottom),
            control: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - radius),
            control: CGPoint(x: left, y: bottom)
        )
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: top),
            control: CGPoint(x: left, y: top)
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
struct SpeechBubbleView: View {
    let text: String
    var response: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(PipoTheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let response, !response.isEmpty {
                Text(response)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.deepPink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Pipo says: \\(response)")
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 17)
        .background {
            PipoSpeechBubbleShape()
                .fill(.white)
        }
        .overlay {
            PipoSpeechBubbleShape()
                .stroke(PipoTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("pipo.onboarding.speech")
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
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? PipoTheme.deepPink : PipoTheme.green)
                .frame(width: 42, height: 42)
                .background(
                    selected ? PipoTheme.palePink : PipoTheme.mint.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12)
                )
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
        SelectableOptionCard(symbol: "airplane", title: "Dream Trip", selected: true)
        Button("CONTINUE") {}
            .buttonStyle(TactileButtonStyle())
    }
    .padding()
    .background(PipoTheme.cream)
}
