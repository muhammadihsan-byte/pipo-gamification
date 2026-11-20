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

    private let onSubmit: (AuthCredentials) -> Void
    private let onAppleSignIn: () -> Void
    private let onGoogleSignIn: () -> Void
    private let onForgotPassword: (String) -> Void

    init(
        initialEmail: String = "",
        onSubmit: @escaping (AuthCredentials) -> Void,
        onAppleSignIn: @escaping () -> Void,
        onGoogleSignIn: @escaping () -> Void,
        onForgotPassword: @escaping (String) -> Void
    ) {
        _email = State(initialValue: initialEmail)
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
                credentialsForm
                submitButton
                if AuthProviderAvailability.socialSignInEnabled {
                    providerDivider
                    providerButtons
                }
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
                Text("Pipo")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PipoTheme.ink)
                Text(".")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PipoTheme.pink)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("🇺🇸")
                Text("EN")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(PipoTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PipoTheme.cream, in: Capsule())
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
        .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }

    private func modeButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? PipoTheme.ink : PipoTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .shadow(color: PipoTheme.ink.opacity(0.06), radius: 3, y: 1)
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
                    .foregroundStyle(PipoTheme.ink)
                HStack(spacing: 10) {
                    Image(systemName: "at")
                        .foregroundStyle(PipoTheme.muted.opacity(0.8))
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
                        .foregroundStyle(PipoTheme.ink)
                    Spacer()
                    Button("Forgot Password?") {
                        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard address.contains("@"), !address.contains(" ") else {
                            validationMessage = "Enter your email address to receive a reset link."
                            return
                        }
                        validationMessage = nil
                        onForgotPassword(address)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PipoTheme.pink)
                    .accessibilityIdentifier("pipo.auth.forgotPassword")
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(PipoTheme.muted.opacity(0.8))
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
                            .foregroundStyle(PipoTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
                .authFieldStyle()
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(PipoTheme.deepPink)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private var submitButton: some View {
        Button {
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
        } label: {
            Text(isSignUp ? "CREATE ACCOUNT" : "SIGN IN NOW")
        }
        .buttonStyle(PrimaryActionButtonStyle())
    }

    private var providerDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(PipoTheme.border).frame(height: 1)
            Text("OR CONTINUE WITH")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize()
            Rectangle().fill(PipoTheme.border).frame(height: 1)
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
                        .foregroundStyle(PipoTheme.ink)
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
            .foregroundStyle(PipoTheme.ink)
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

@MainActor
private extension View {
    func authFieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(height: 48)
            .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(PipoTheme.border, lineWidth: 1)
            }
    }
}

/// A verified recovery callback is required before presenting this editor.
/// The sheet cannot swipe away into an authenticated dashboard.
@MainActor
struct PasswordResetView: View {
    @State private var password = ""
    @State private var confirmation = ""
    @State private var feedback: String?
    @State private var isWorking = false

    let onSubmit: @MainActor (String) async throws -> Void
    let onCancel: @MainActor () async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a new password")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PipoTheme.ink)
                Text("Your password must be at least 8 characters.")
                    .foregroundStyle(PipoTheme.muted)
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .authFieldStyle()
                SecureField("Confirm new password", text: $confirmation)
                    .textContentType(.newPassword)
                    .authFieldStyle()
                if let feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.deepPink)
                        .accessibilityAddTraits(.isStaticText)
                }
                Button(isWorking ? "Updating…" : "UPDATE PASSWORD") {
                    guard password.count >= 8 else {
                        feedback = "Use at least 8 characters."
                        return
                    }
                    guard password == confirmation else {
                        feedback = "Passwords don't match."
                        return
                    }
                    feedback = nil
                    isWorking = true
                    Task { @MainActor in
                        defer { isWorking = false }
                        do { try await onSubmit(password) }
                        catch { feedback = error.localizedDescription }
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isWorking)
                Spacer()
            }
            .padding(24)
            .background(.white)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isWorking = true
                        Task { @MainActor in
                            defer { isWorking = false }
                            do { try await onCancel() }
                            catch { feedback = error.localizedDescription }
                        }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    AuthView(
        initialEmail: MockData.authEmail,
        onSubmit: { _ in },
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onForgotPassword: { _ in }
    )
}
