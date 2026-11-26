import Foundation
import SwiftUI

struct AuthCredentials: Sendable {
    let email: String
    let password: String
    let isSignUp: Bool
}

@MainActor
struct AuthView: View {
    private enum Page: Hashable {
        case welcome, signIn, signUp
    }

    @State private var page: Page = .welcome
    @State private var email: String
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var validationMessage: String?
    @State private var mascotReactionID = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if page == .welcome {
                        welcomeContent
                            .frame(minHeight: geometry.size.height)
                    } else {
                        credentialsContent
                    }
                }
                .pipoPageTransition(value: page)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(.white)
        .preferredColorScheme(.light)
        .onChange(of: validationMessage) { _, message in
            if message != nil { mascotReactionID += 1 }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            brandHeader
            Spacer(minLength: 22)
            PipoMascotView(companion: .idle)
                .frame(height: geometrySafeHeroHeight)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    authSpeechBubble("Ready for a little win?")
                        .padding(.top, 8)
                }
             Text("SMALL STEPS. BIG DREAMS.")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(PipoTheme.cardAccentReadable)
                .padding(.top, 18)
            Text("Saving can be fun, actually.")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.cardInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 325)
                .padding(.top, 10)
            Text("Meet Pipo. Your tiny cheerleader for the goals that matter.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.cardMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer(minLength: 28)
            Button("Get started") { open(.signUp) }
                .buttonStyle(AuthPrimaryButtonStyle())
                .accessibilityIdentifier("pipo.auth.getStarted")
            Button("I already have an account") { open(.signIn) }
                .buttonStyle(AuthOutlineButtonStyle())
                .padding(.top, 11)
                .accessibilityIdentifier("pipo.auth.existingAccount")
            Text("No bank connection needed. Track what you save.")
                .font(.caption2)
                .foregroundStyle(PipoTheme.cardMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var brandHeader: some View {
        HStack {
            brandName
            Spacer()
            Text("YOUR SAVING BUDDY")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(PipoTheme.cardAccentReadable)
        }
        .frame(minHeight: 44)
    }

    private var brandName: some View {
        Text("pipo.")
            .font(.system(size: 25, weight: .heavy, design: .rounded))
            .foregroundStyle(PipoTheme.cardInk)
    }

    private var credentialsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    open(.welcome)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(PipoTheme.cardMuted)
                .accessibilityIdentifier("pipo.auth.back")
                Spacer()
                brandName
            }
            PipoMascotView(companion: .reassurance, reaction: .reassure, reactionID: mascotReactionID)
                .accessibilityHidden(true)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 136 : 160)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    authSpeechBubble(page == .signUp ? "I've got your back!" : "Missed you!")
                }
                 .padding(.top, 8)
            Text(page == .signUp ? "Let's get started!" : "You're back!")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(PipoTheme.cardInk)
                .padding(.top, 16)
            Text(page == .signUp
                 ? "Big dreams start with little steps."
                 : "Your saving journey is right here.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.cardMuted)
                .padding(.top, 4)
            Text(page == .signUp
                 ? "Create an account with your email. Pipo tracks what you save; it does not hold or move your money."
                 : "Welcome back. Continue with the email account you used before.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.cardMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 16)
            credentialsForm
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 18)
            submitButton
                .padding(.top, 18)
            if AuthProviderAvailability.socialSignInEnabled {
                providerDivider.padding(.top, 22)
                providerButtons.padding(.top, 18)
            }
            HStack(spacing: 5) {
                Text(page == .signUp ? "Already have an account?" : "New around here?")
                    .foregroundStyle(PipoTheme.cardMuted)
                Button(page == .signUp ? "Log in" : "Create account") {
                    open(page == .signUp ? .signIn : .signUp)
                }
                .foregroundStyle(PipoTheme.cardAccentReadable)
                .fontWeight(.bold)
                .accessibilityIdentifier("pipo.auth.switchMode")
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
            Text(page == .signUp
                 ? "You may need to confirm your email before signing in."
                 : "Need account access? Use Forgot Password above.")
                .font(.caption)
                .foregroundStyle(PipoTheme.cardMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private var geometrySafeHeroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 225 : 290
    }

    private func authSpeechBubble(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PipoTheme.cardAccentReadable)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(PipoTheme.palePink, lineWidth: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 152)
    }

    private func open(_ destination: Page) {
        page = destination
        password = ""
        isPasswordVisible = false
        validationMessage = nil
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
                    if page == .signIn {
                        Button {
                            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard address.contains("@"), !address.contains(" ") else {
                                validationMessage = "Enter your email address to receive a reset link."
                                return
                            }
                            validationMessage = nil
                            onForgotPassword(address)
                        } label: {
                            // Put the 44pt minimum on the label, not only
                            // the outer Button. XCTest measured only 26.3pt
                            // for the earlier outer frame at accessibility M.
                            Text("Forgot Password?")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PipoTheme.cardAccentReadable)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pipo.auth.forgotPassword")
                    }
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
                    .textContentType(page == .signUp ? .newPassword : .password)
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundStyle(PipoTheme.muted)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    .accessibilityIdentifier("pipo.auth.passwordVisibility")
                }
                .authFieldStyle()
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(PipoTheme.deepPink)
                    .accessibilityLabel(validationMessage)
                    .accessibilityIdentifier("pipo.auth.validation")
                    .transition(.opacity)
            }
        }
        .pipoAnimate(validationMessage != nil)
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
                    isSignUp: page == .signUp
                )
            )
        } label: {
            Text(page == .signUp ? "Create account" : "Sign in")
        }
        .buttonStyle(AuthPrimaryButtonStyle())
        .accessibilityIdentifier("pipo.auth.submit")
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

/// Match the approved Pipo primary CTA across auth and saving flows.
@MainActor
private struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(PipoTheme.primaryActionText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .background(
                configuration.isPressed ? PipoTheme.deepPink : PipoTheme.approvedActionPink,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .pipoPressFeedback(configuration.isPressed)
    }
}

@MainActor
private struct AuthOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PipoTheme.cardInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                configuration.isPressed ? PipoTheme.cream : .white,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(PipoTheme.cardBorder, lineWidth: 1)
            }
            .pipoPressFeedback(configuration.isPressed)
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
            .pipoPressFeedback(configuration.isPressed)
    }
}

@MainActor
private extension View {
    func authFieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 52)
            .padding(.vertical, 4)
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
