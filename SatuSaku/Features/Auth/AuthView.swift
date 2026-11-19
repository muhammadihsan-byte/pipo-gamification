import Foundation
import SwiftUI

struct AuthCredentials: Sendable {
    let email: String
    let password: String
    let isSignUp: Bool
}

@MainActor
struct AuthView: View {
    @State private var isSignUp = false
    @State private var email: String
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var validationMessage: String?

    private let isSubmitting: Bool
    private let onSubmit: (AuthCredentials) -> Void
    private let onAppleSignIn: () -> Void
    private let onGoogleSignIn: () -> Void
    private let onForgotPassword: () -> Void

    init(
        initialEmail: String = "",
        isSubmitting: Bool = false,
        onSubmit: @escaping (AuthCredentials) -> Void,
        onAppleSignIn: @escaping () -> Void,
        onGoogleSignIn: @escaping () -> Void,
        onForgotPassword: @escaping () -> Void
    ) {
        _email = State(initialValue: initialEmail)
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        self.onAppleSignIn = onAppleSignIn
        self.onGoogleSignIn = onGoogleSignIn
        self.onForgotPassword = onForgotPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                brandHeader
                heroArtwork
                signInModePicker
                    .disabled(isSubmitting)
                credentialsForm
                    .disabled(isSubmitting)
                submitButton
                providerDivider
                providerButtons
                    .disabled(isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var brandHeader: some View {
        HStack {
            HStack(spacing: 0) {
                Text("pipo")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(SatuSakuTheme.ink)
                Text(".")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(SatuSakuTheme.pink)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("🇺🇸")
                Text("EN")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SatuSakuTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SatuSakuTheme.cream, in: Capsule())
        }
        .frame(height: 42)
    }

    private var heroArtwork: some View {
        PipoMascotView(state: .idle)
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var signInModePicker: some View {
        HStack(spacing: 4) {
            modeButton(title: "Sign In", selected: !isSignUp) {
                isSignUp = false
            }
            modeButton(title: "Sign Up", selected: isSignUp) {
                isSignUp = true
            }
        }
        .padding(4)
        .background(SatuSakuTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }

    private func modeButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? SatuSakuTheme.ink : SatuSakuTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .shadow(color: SatuSakuTheme.ink.opacity(0.06), radius: 3, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Email Address")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SatuSakuTheme.ink)
                HStack(spacing: 10) {
                    Image(systemName: "at")
                        .foregroundStyle(SatuSakuTheme.muted.opacity(0.8))
                    TextField("example@gmail.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .authFieldStyle()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SatuSakuTheme.ink)
                    Spacer()
                    Button("Forgot Password?") {
                        onForgotPassword()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SatuSakuTheme.pink)
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(SatuSakuTheme.muted.opacity(0.8))
                    Group {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(isSignUp ? .newPassword : .password)
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(SatuSakuTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
                .authFieldStyle()
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(SatuSakuTheme.deepPink)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private var submitButton: some View {
        PipoPrimaryButton(
            isSignUp ? "CREATE ACCOUNT" : "SIGN IN NOW",
            isLoading: isSubmitting,
            loadingTitle: isSignUp ? "CREATING ACCOUNT…" : "SIGNING IN…"
        ) {
            guard !isSubmitting else { return }
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEmail.isEmpty, !password.isEmpty else {
                validationMessage = "Enter your email and password."
                return
            }
            validationMessage = nil
            onSubmit(
                AuthCredentials(
                    email: trimmedEmail,
                    password: password,
                    isSignUp: isSignUp
                )
            )
        }
    }

    private var providerDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(SatuSakuTheme.border).frame(height: 1)
            Text("OR CONTINUE WITH")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(SatuSakuTheme.muted)
                .fixedSize()
            Rectangle().fill(SatuSakuTheme.border).frame(height: 1)
        }
    }

    private var providerButtons: some View {
        HStack(spacing: 12) {
            Button(action: onAppleSignIn) {
                Label("Apple", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(ProviderButtonStyle())

            Button(action: onGoogleSignIn) {
                HStack(spacing: 8) {
                    Text("G")
                        .font(.headline.bold())
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    Text("Google")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SatuSakuTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(ProviderButtonStyle())
        }
    }
}

@MainActor
private struct ProviderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SatuSakuTheme.ink)
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

@MainActor
private extension View {
    func authFieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(height: 48)
            .background(SatuSakuTheme.cream, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
            }
    }
}

#Preview {
    AuthView(
        initialEmail: MockData.authEmail,
        onSubmit: { _ in },
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onForgotPassword: {}
    )
}
