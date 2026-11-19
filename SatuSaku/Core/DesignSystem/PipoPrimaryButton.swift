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
    let loadingTitle: String?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        _ title: String,
        state: PipoPrimaryButtonState = .default,
        isLoading: Bool = false,
        loadingTitle: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.state = state
        self.isLoading = isLoading
        self.loadingTitle = loadingTitle
        self.action = action
    }

    private var isBusy: Bool {
        isLoading || state == .loading
    }

    private var isDisabled: Bool {
        state == .disabled || isBusy
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(PipoColors.textPrimary)
                }
                Text(isBusy ? (loadingTitle ?? "Loading…") : title)
            }
        }
        .buttonStyle(PipoPrimaryButtonStyle(state: state, isLoading: isLoading, isFocused: isFocused))
        .disabled(isDisabled)
        .focusable(true)
        .focused($isFocused)
        .contentShape(Rectangle())
        .accessibilityLabel(isBusy ? "\(title), loading" : title)
        .accessibilityValue(isBusy ? "Loading" : "")
        .accessibilityHint(isBusy ? "Please wait" : (isDisabled ? "This action is unavailable" : ""))
    }
}

private struct PipoPrimaryButtonStyle: ButtonStyle {
    let state: PipoPrimaryButtonState
    let isLoading: Bool
    let isFocused: Bool

    @Environment(\.isEnabled) private var isEnabled

    // Candidate interaction colors from Figma 813:441.
    // Keep these component-local until the design tokens are approved.
    private let pressedFill = Color(red: 233 / 255, green: 79 / 255, blue: 110 / 255)
    private let loadingFill = Color(red: 251 / 255, green: 97 / 255, blue: 128 / 255)

    func makeBody(configuration: Configuration) -> some View {
        let busy = isLoading || state == .loading
        let disabled = state == .disabled || !isEnabled
        let pressed = configuration.isPressed && !disabled && !busy
        let focused = state == .focus

        configuration.label
            .font(.footnote.weight(.heavy))
            .tracking(1.5)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foregroundColor(disabled: disabled, pressed: pressed, busy: busy))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor(disabled: disabled, pressed: pressed, busy: busy))
                    .padding(.vertical, 6)
            }
            .overlay(alignment: .center) {
                if focused || isFocused {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PipoColors.accentStrong, lineWidth: 2)
                        .padding(.vertical, 6)
                }
            }
            .scaleEffect(pressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private func backgroundColor(disabled: Bool, pressed: Bool, busy: Bool) -> Color {
        if busy {
            return loadingFill
        }
        if disabled {
            return PipoColors.surfaceMuted
        }
        if pressed {
            return pressedFill
        }
        return PipoColors.accentPrimary
    }

    private func foregroundColor(disabled: Bool, pressed: Bool, busy: Bool) -> Color {
        if busy {
            return PipoColors.textPrimary
        }
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

            PipoPrimaryButton("Sign In Now", state: .loading, isLoading: true, loadingTitle: "Signing in…", action: {})

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
