import SwiftUI

enum PipoPrimaryButtonState: Equatable {
    case `default`
    case disabled
    case loading
    case focus
    case hover
}

struct PipoPrimaryButton: View {
    let title: String
    let state: PipoPrimaryButtonState
    let isLoading: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        _ title: String,
        state: PipoPrimaryButtonState = .default,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.isLoading = isLoading
        self.action = action
    }

    private var isDisabled: Bool {
        state == .disabled || isLoading
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(PipoColors.textPrimary)
                }
                Text(isLoading ? "Signing in…" : title)
            }
        }
        .buttonStyle(PipoPrimaryButtonStyle(state: state, isLoading: isLoading, isFocused: isFocused))
        .disabled(isDisabled)
        .focusable(true)
        .focused($isFocused)
        .contentShape(Rectangle())
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
        .accessibilityValue(isLoading ? "Loading" : "")
        .accessibilityAddTraits(isDisabled ? .isDisabled : [])
        .accessibilityHint(isDisabled ? "This action is unavailable" : "")
    }
}

private struct PipoPrimaryButtonStyle: ButtonStyle {
    let state: PipoPrimaryButtonState
    let isLoading: Bool
    let isFocused: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let disabled = state == .disabled || !isEnabled || isLoading
        let pressed = configuration.isPressed && !disabled
        let focused = state == .focus

        configuration.label
            .font(.footnote.weight(.heavy))
            .tracking(1.5)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foregroundColor(disabled: disabled, pressed: pressed))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor(disabled: disabled, pressed: pressed))
                    .frame(height: 32)
            }
            .overlay(alignment: .center) {
                if focused || isFocused {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PipoColors.accentStrong, lineWidth: 2)
                        .frame(height: 32)
                }
            }
            .scaleEffect(pressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private func backgroundColor(disabled: Bool, pressed: Bool) -> Color {
        if disabled {
            return PipoColors.surfaceMuted
        }
        if pressed {
            return PipoColors.accentStrong
        }
        return PipoColors.accentPrimary
    }

    private func foregroundColor(disabled: Bool, pressed: Bool) -> Color {
        if disabled {
            return PipoColors.textSecondary
        }
        if pressed {
            return PipoColors.textStrong
        }
        return PipoColors.textPrimary
    }
}

#Preview("Pipo Primary Button States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pipo Primary Button")
                .font(.title2.bold())

            PipoPrimaryButton("Sign In Now", action: {})

            PipoPrimaryButton("Pressed Candidate", state: .default, action: {})

            PipoPrimaryButton("Signing in…", state: .loading, isLoading: true, action: {})

            PipoPrimaryButton("Sign In Now", state: .disabled, action: {})

            PipoPrimaryButton("Keyboard Focus", state: .focus, action: {})

            Text("Candidate comparison")
                .font(.headline)

            HStack(spacing: 12) {
                PipoPrimaryButton("Accessible", action: {})
                Button("Original") {}
                    .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .padding(24)
    }
}
