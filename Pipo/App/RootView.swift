import SwiftData
import Supabase
import SwiftUI
import WidgetKit

@MainActor
struct RootView: View {
    @State private var navigationManager: NavigationManager
    @State private var authStateManager: AuthStateManager
    @State private var subscriptionManager: SubscriptionManager
    @State private var storeKitManager: StoreKitManager
    @State private var supabaseService: SupabaseService?
    @State private var choosingPlan = false
    @State private var showingAccountDeletion = false
    @State private var isDeletingAccount = false
    @State private var isSigningOut = false
    @State private var isResettingPassword = false
    @State private var isRecoveringSession = false
    @State private var noticeMessage: String?
    @State private var hasFinishedOnboardingQA = false
    @State private var completedOnboardingAccountID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var localTransactions: [SavingTransaction]
    @Query private var localGoals: [PersonalGoal]

    private let supabaseConfigurationError: String?

    private var isOnboardingQA: Bool {
        #if DEBUG
        (ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa") || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa-returning"))
        #else
        false
        #endif
    }

    private var needsOnboarding: Bool {
        #if DEBUG
        // Returning-user simulator fixtures must not depend on whether a
        // previous test happened to create an onboarding profile.
        if ProcessInfo.processInfo.arguments.contains("-pipo-dashboard-qa") {
            return false
        }
        if ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa") {
            return !hasFinishedOnboardingQA
        }
        #endif
        guard let userID = authStateManager.userID else { return false }
        if completedOnboardingAccountID == userID { return false }
        return OnboardingProfileStore.load(for: userID) == nil
    }

    init(
        initialAuthState: AuthState = .unauthenticated,
        initialRoute: Route? = nil
    ) {
        _navigationManager = State(
            initialValue: NavigationManager(initialRoute: initialRoute)
        )
        // A fixed test-only user lets remote QA prove per-account personalization
        // without using credentials, network calls or a real customer account.
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let qaSignedIn = args.contains("-pipo-onboarding-qa")
            || args.contains("-pipo-onboarding-qa-returning")
            || args.contains("-pipo-visual-qa")
            || args.contains("-pipo-dashboard-qa")
        let onboardingQAUserID = qaSignedIn
            ? UUID(uuidString: "99999999-9999-4999-8999-999999999999")
            : nil
        #else
        let onboardingQAUserID: UUID? = nil
        #endif
        _authStateManager = State(
            initialValue: AuthStateManager(
                initialState: initialAuthState,
                userID: onboardingQAUserID
            )
        )
        _subscriptionManager = State(initialValue: SubscriptionManager())
        do {
            let service = try SupabaseService.fromEnvironment()
            _supabaseService = State(initialValue: service)
            _storeKitManager = State(initialValue: StoreKitManager(supabaseService: service))
            supabaseConfigurationError = nil
        } catch {
            _supabaseService = State(initialValue: nil)
            _storeKitManager = State(initialValue: StoreKitManager())
            supabaseConfigurationError = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack(path: $navigationManager.path) {
            rootContent
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(navigationManager)
        .environment(authStateManager)
        .environment(subscriptionManager)
        .environment(storeKitManager)
        .tint(PipoTheme.green)
        .task {
            // Complete a previously confirmed server deletion if the device
            // failed to save its local cleanup before app termination.
            AccountDeletionLocalData.retryPending(in: modelContext)
        }
        .task {
            // Restore the active widget account even when the initial screen
            // is an authenticated simulator fixture.
            updateWidgetAccount(authStateManager.userID)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-auth-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-dashboard-qa")
                || (ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa") || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa-returning")) { return }
            #endif
            guard let supabaseService else { return }
            await supabaseService.observeAuthStateChanges(using: authStateManager)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-auth-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-dashboard-qa")
                || (ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa") || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa-returning")) { return }
            #endif
            if authStateManager.userID == nil {
                clearWidgetSnapshot()
            }
            storeKitManager.startTransactionUpdates(
                modelContext: modelContext,
                subscriptionManager: subscriptionManager
            ) { error in
                noticeMessage = error.localizedDescription
            }
            await storeKitManager.loadProduct()
            if let userID = authStateManager.userID {
                do {
                    try await storeKitManager.restorePurchasedSlots(
                        userID: userID,
                        modelContext: modelContext,
                        subscriptionManager: subscriptionManager,
                        isCurrentAccount: { authStateManager.userID == userID }
                    )
                } catch {
                    noticeMessage = "Purchased slots could not sync: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: authStateManager.authState) { _, authState in
            if authState == .unauthenticated {
                navigationManager.resetAccountContext()
                subscriptionManager.updateEntitlements(
                    purchasedPersonalSlots: 0, purchasedGroupSlots: 0
                )
                clearWidgetSnapshot()
            } else {
                navigationManager.resetAccountContext()
                // Onboarding runs after authentication, never before it.
                // Account-scoped completion state is read by rootContent.
            }
        }
        .onChange(of: authStateManager.userID) { _, userID in
            // Invalidate widget content and pending deposit/milestone routes
            // BEFORE exposing the new account's dashboard.
            navigationManager.resetAccountContext()
            if !isDeletingAccount { noticeMessage = nil }
            // Entitlements from account A must not remain usable by account B
            // while B's StoreKit profile restoration is pending.
            subscriptionManager.updateEntitlements(
                purchasedPersonalSlots: 0, purchasedGroupSlots: 0
            )
            updateWidgetAccount(userID)
            guard let userID, !isDeletingAccount, !isRecoveringSession else { return }
            // Do not wait for StoreKit before retrying local-only goal sync.
            enqueuePersonalSavingsSync(for: userID)
            Task {
                guard authStateManager.userID == userID else { return }
                do {
                    try await storeKitManager.restorePurchasedSlots(
                        userID: userID,
                        modelContext: modelContext,
                        subscriptionManager: subscriptionManager,
                        isCurrentAccount: { authStateManager.userID == userID }
                    )
                } catch {
                    guard authStateManager.userID == userID else { return }
                    noticeMessage = "Purchased slots could not be verified: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A failed offline write remains local; retry on foreground,
            // without inventing a successful server sync or a timer.
            if phase == .active, !isDeletingAccount, !isRecoveringSession,
               let userID = authStateManager.userID {
                enqueuePersonalSavingsSync(for: userID, showFailure: false)
            }
        }
        .onOpenURL { url in
            guard !isDeletingAccount else { return }
            if url.scheme == "pipo", url.host == "log-deposit" {
                guard
                    let goalIDString = URLComponents(
                        url: url,
                        resolvingAgainstBaseURL: false
                    )?.queryItems?.first(where: { $0.name == "goal" })?.value,
                    let goalID = UUID(uuidString: goalIDString)
                else {
                    noticeMessage = "The widget link does not include a valid saving goal."
                    return
                }
                guard authStateManager.authState == .authenticated,
                      AccountScope.visibleGoals(localGoals, userID: authStateManager.userID)
                        .contains(where: { $0.id == goalID && !$0.isGroupGoal && $0.progress < 1 })
                else {
                    noticeMessage = "This saving goal isn't available for the signed-in account."
                    return
                }
                navigationManager.requestDeposit(goalID: goalID)
                return
            }

            guard let supabaseService else { return }
            let isRecovery = supabaseService.configuration.isPasswordRecoveryCallback(url)
            guard isRecovery || supabaseService.configuration.isSignInCallback(url) else {
                return
            }
            // Recovery login must not show the normal dashboard during the
            // transient password-editor session.
            if isRecovery { isRecoveringSession = true }
            Task {
                do {
                    try await supabaseService.handleAuthCallback(
                        url,
                        authStateManager: authStateManager
                    )
                    if isRecovery { isResettingPassword = true }
                } catch {
                    if isRecovery {
                        // If the provider accepted a partial session, never
                        // leave it open on the normal dashboard.
                        do {
                            try await supabaseService.signOut(authStateManager: authStateManager)
                            isRecoveringSession = false
                        } catch {
                            noticeMessage = "Recovery failed. Close and reopen Pipo to try again."
                            return
                        }
                    }
                    noticeMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $isResettingPassword) {
            PasswordResetView(
                onSubmit: { password in
                    guard let supabaseService else {
                        throw SupabaseServiceError.notAuthenticated
                    }
                    try await supabaseService.updateRecoveredPassword(password)
                    try await supabaseService.signOut(authStateManager: authStateManager)
                    isResettingPassword = false
                    isRecoveringSession = false
                    noticeMessage = "Password updated. Sign in with your new password."
                },
                onCancel: {
                    guard let supabaseService else {
                        throw SupabaseServiceError.notAuthenticated
                    }
                    try await supabaseService.signOut(authStateManager: authStateManager)
                    isResettingPassword = false
                    isRecoveringSession = false
                }
            )
        }
        .sheet(isPresented: $showingAccountDeletion) {
            AccountDeletionConfirmationView(onDelete: performAccountDeletion)
        }
        .sheet(isPresented: $navigationManager.isMilestonePresented) {
            ConsistencyMilestoneView(
                xpEarned: navigationManager.milestoneXPEarned,
                streakDays: navigationManager.milestoneStreakDays,
                badgeTitles: navigationManager.milestoneNewBadges,
                onViewAchievements: {
                    navigationManager.requestAchievementsOpen()
                    navigationManager.isMilestonePresented = false
                }
            )
        }
        .alert(
            "Pipo",
            isPresented: Binding(
                get: { noticeMessage != nil },
                set: { if !$0 { noticeMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                noticeMessage = nil
            }
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if isRecoveringSession {
            VStack(spacing: 12) {
                ProgressView()
                Text("Securing your password recovery…")
                    .font(.footnote)
                    .foregroundStyle(PipoTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        } else {
            switch authStateManager.authState {
            case .unauthenticated:
                authenticationView
            case .authenticated:
                if needsOnboarding {
                    onboardingView
                } else {
                    dashboardView
                }
            }
        }
    }

    private var onboardingView: some View {
        OnboardingContainerView { personalization in
            if isOnboardingQA {
                if let userID = authStateManager.userID {
                    _ = OnboardingProfileStore.save(personalization, for: userID)
                }
                hasFinishedOnboardingQA = true
                return
            }
            guard let userID = authStateManager.userID else {
                noticeMessage = "Sign in to save your Pipo preferences."
                return
            }
            if OnboardingProfileStore.save(personalization, for: userID) {
                completedOnboardingAccountID = userID
                navigationManager.popToRoot()
            } else {
                noticeMessage = "Your Pipo preferences could not be saved. Please try again."
            }
        }
    }

    private var authenticationView: some View {
        AuthView(
            onSubmit: authenticate,
            onAppleSignIn: {
                beginOAuthSignIn(provider: .apple)
            },
            onGoogleSignIn: {
                beginOAuthSignIn(provider: .google)
            },
            onForgotPassword: requestPasswordReset
        )
    }

    private var dashboardView: some View {
        DashboardView(
            onCreateGoal: {
                choosingPlan = true
            },
            onDeleteAccount: {
                guard authStateManager.authState == .authenticated,
                      authStateManager.userID != nil,
                      !isSigningOut, !isDeletingAccount else { return }
                showingAccountDeletion = true
            },
            onSignOut: signOutCurrentAccount,
            onSavingCompleted: { transaction, goal, xpEarned, streakDays, badges in
                guard !isDeletingAccount,
                      let userID = authStateManager.userID,
                      AccountScope.owns(goal, userID: userID),
                      transaction.userID == userID else { return }
                navigationManager.transactionDidComplete(
                    xpEarned: xpEarned,
                    streakDays: streakDays,
                    badgeTitles: badges.map(\.title)
                )
                // Group plans are not shared or sent to other people yet.
                // Only personal goals have deployed cloud ownership rules.
                guard !goal.isGroupGoal, let supabaseService else { return }
                Task {
                    guard authStateManager.userID == userID else { return }
                    do {
                        try await supabaseService.syncPersonalSavings(
                            goals: [goal], transactions: [transaction],
                            authenticatedUserID: userID
                        )
                    } catch {
                        guard authStateManager.userID == userID else { return }
                        noticeMessage = "Saved on this device, but cloud backup failed: \(error.localizedDescription)"
                    }
                }
            }
        )
        .confirmationDialog("Choose a saving plan", isPresented: $choosingPlan, titleVisibility: .visible) {
            Button("Personal saving") { navigationManager.navigate(to: .createGoal) }
            Button("Group saving") { navigationManager.navigate(to: .createGroupPlan) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// No local data is removed unless the authenticated server endpoint
    /// explicitly confirms hard deletion of this exact Auth user.
    private func performAccountDeletion() async throws {
        guard !isDeletingAccount,
              let userID = authStateManager.userID,
              authStateManager.authState == .authenticated,
              let supabaseService
        else {
            throw SupabaseServiceError.notAuthenticated
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }
        try await supabaseService.deleteCurrentAccount(accountID: userID)

        // The Auth identity is gone. If saving the local store fails, persist
        // the deleted ID so cleanup can retry offline on the next launch.
        AccountDeletionLocalData.markServerDeleted(userID)
        storeKitManager.discardDeletedAccountPurchaseContext(userID)
        var localCleanupFailure: Error?
        do {
            try AccountDeletionLocalData.complete(for: userID, in: modelContext)
        } catch {
            localCleanupFailure = error
        }

        var widgetCleared = true
        if authStateManager.userID == userID {
            await supabaseService.discardDeletedSession(using: authStateManager)
            widgetCleared = updateWidgetAccount(nil)
        }
        showingAccountDeletion = false
        noticeMessage = localCleanupFailure == nil && widgetCleared
            ? "Your Pipo account and its saved data were deleted."
            : "Your Pipo account was deleted on the server. Some device data or widget content could not be cleared; Pipo will retry cleanup when you next open the app."
    }

    private func signOutCurrentAccount() {
        guard !isSigningOut, !isDeletingAccount, !isRecoveringSession,
              authStateManager.authState == .authenticated,
              let signedInID = authStateManager.userID,
              let supabaseService else { return }
        isSigningOut = true
        Task {
            defer { isSigningOut = false }
            guard authStateManager.userID == signedInID else { return }
            do {
                try await supabaseService.signOut(authStateManager: authStateManager)
                // Account changes clear widget state, navigation and entitlements.
                navigationManager.resetAccountContext()
            } catch {
                guard authStateManager.userID == signedInID else { return }
                noticeMessage = "Couldn't sign out. Please check your connection and try again."
            }
        }
    }

    private func requestPasswordReset(_ email: String) {
        guard let supabaseService else {
            noticeMessage = supabaseConfigurationError ?? "Supabase is not configured."
            return
        }
        Task {
            do {
                try await supabaseService.requestPasswordReset(email: email)
                // Do not confirm whether the email address is registered.
                noticeMessage = "If an account exists, a password reset link will arrive by email."
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    private func authenticate(_ credentials: AuthCredentials) {
        guard let supabaseService else {
            noticeMessage = supabaseConfigurationError ?? "Supabase is not configured."
            return
        }

        Task {
            do {
                if credentials.isSignUp {
                    let needsConfirmation = try await supabaseService.signUp(
                        email: credentials.email,
                        password: credentials.password,
                        authStateManager: authStateManager
                    )
                    if needsConfirmation {
                        noticeMessage = "Check your email for a confirmation link."
                    }
                } else {
                    try await supabaseService.signIn(
                        email: credentials.email,
                        password: credentials.password,
                        authStateManager: authStateManager
                    )
                }
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    private func enqueuePersonalSavingsSync(
        for userID: UUID, showFailure: Bool = true
    ) {
        guard !isDeletingAccount, !isRecoveringSession,
              authStateManager.authState == .authenticated,
              authStateManager.userID == userID,
              let supabaseService else { return }

        // Never fetch another user's goals, group-only drafts, or
        // quarantined ownerless records into a network batch.
        let allGoals = (try? modelContext.fetch(FetchDescriptor<PersonalGoal>())) ?? localGoals
        let allTransactions = (try? modelContext.fetch(FetchDescriptor<SavingTransaction>()))
            ?? localTransactions
        let personalGoals = AccountScope.visibleGoals(allGoals, userID: userID)
            .filter { !$0.isGroupGoal }
        let personalGoalIDs = Set(personalGoals.map(\.id))
        let ownedTransactions = AccountScope.visibleTransactions(
            allTransactions, goals: allGoals, userID: userID
        ).filter { personalGoalIDs.contains($0.goalId) }
        guard !personalGoals.isEmpty else { return }

        Task {
            guard authStateManager.userID == userID else { return }
            do {
                try await supabaseService.syncPersonalSavings(
                    goals: personalGoals, transactions: ownedTransactions,
                    authenticatedUserID: userID
                )
            } catch {
                guard authStateManager.userID == userID else { return }
                if showFailure {
                    noticeMessage = "Saved on this device, but cloud backup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearWidgetSnapshot() {
        updateWidgetAccount(nil)
    }

    @discardableResult
    private func updateWidgetAccount(_ userID: UUID?) -> Bool {
        var success = true
        do {
            try WidgetSharedData.activate(userID: userID)
            if userID == nil {
                try WidgetSharedData.save(.empty)
            }
        } catch {
            success = false
            noticeMessage = "Widget account data could not be updated: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        return success
    }

    private func beginOAuthSignIn(provider: Provider) {
        guard let supabaseService else {
            noticeMessage = supabaseConfigurationError ?? "Supabase is not configured."
            return
        }

        Task {
            do {
                try await supabaseService.signInWithOAuth(
                    provider: provider,
                    authStateManager: authStateManager
                )
                navigationManager.popToRoot()
            } catch {
                noticeMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .auth:
            authenticationView
        case .dashboard:
            dashboardView
        case .createGoal:
            CreateGoalView(
                onBack: navigationManager.pop,
                onCreated: { goalID in
                    navigationManager.popToRoot()
                    navigationManager.navigate(to: .personalGoal(goalID))
                    if let userID = authStateManager.userID {
                        // Fetch from SwiftData, not @Query's potentially stale
                        // post-save snapshot, so newly created plans are queued.
                        enqueuePersonalSavingsSync(for: userID)
                    }
                }
            )
        case .personalGoal(let goalID):
            PersonalGoalDetailView(goalID: goalID, onBack: navigationManager.pop) {
                navigationManager.requestDeposit(goalID: goalID)
            }
        case .createGroupPlan, .savingRhythm, .reviewGroupSaving:
            CreateGroupPlanView(onBack: navigationManager.pop, onDashboard: navigationManager.popToRoot)
        case .milestoneCelebration:
            ConsistencyMilestoneView(
                xpEarned: navigationManager.milestoneXPEarned,
                streakDays: navigationManager.milestoneStreakDays,
                badgeTitles: navigationManager.milestoneNewBadges,
                onViewAchievements: {
                    navigationManager.requestAchievementsOpen()
                    navigationManager.popToRoot()
                }
            )
        case .paywall(let isGroup):
            PaywallView(isGroup: isGroup)
        }
    }

}

/// Destructive action is deliberately separate from the profile entry point.
/// Typing DELETE prevents an accidental single-tap loss of saving history.
@MainActor
private struct AccountDeletionConfirmationView: View {
    let onDelete: @MainActor () async throws -> Void

    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Delete your Pipo account?")
                        .font(.title2.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text("This permanently deletes your Pipo account, your synced personal goals and saving entries, your locally saved personal and group plans, achievements, and personalization. Your widget data will also be cleared.")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.ink)
                    Text("Pipo does not hold your money. Deleting your account will not move money or cancel payments made outside Pipo. This cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.muted)
                    Text("Type DELETE to confirm")
                        .font(.subheadline.weight(.semibold))
                    TextField("DELETE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("pipo.deleteAccount.confirmation")
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("pipo.deleteAccount.error")
                    }
                    Button(role: .destructive) {
                        isWorking = true
                        errorMessage = nil
                        Task { @MainActor in
                            defer { isWorking = false }
                            do {
                                try await onDelete()
                            } catch {
                                // Failed server deletion leaves local data intact.
                                errorMessage = "Deletion was not confirmed. \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(isWorking ? "Deleting account…" : "Delete account permanently")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isWorking || confirmation != "DELETE")
                    .accessibilityIdentifier("pipo.deleteAccount.submit")
                    Button("Keep my account") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isWorking)
                    .accessibilityIdentifier("pipo.deleteAccount.cancel")
                }
                .padding(24)
            }
            .background(.white)
            .navigationTitle("Account deletion")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isWorking)
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RootView()
                .previewDisplayName("Sign In")
            RootView(initialAuthState: .authenticated)
                .previewDisplayName("Dashboard")
            RootView(initialAuthState: .authenticated, initialRoute: .createGroupPlan)
                .previewDisplayName("Group Saving")
            RootView(initialAuthState: .authenticated, initialRoute: .milestoneCelebration)
                .previewDisplayName("Milestone")
        }
        .modelContainer(
            for: [PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self],
            inMemory: true
        )
    }
}
