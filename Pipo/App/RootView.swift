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
    @State private var noticeMessage: String?
    @State private var hasFinishedOnboardingQA = false
    @State private var completedOnboardingAccountID: UUID?
    @Environment(\.modelContext) private var modelContext
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
            // Restore the active widget account even when the initial screen
            // is an authenticated simulator fixture.
            updateWidgetAccount(authStateManager.userID)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-dashboard-qa")
                || (ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa") || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa-returning")) { return }
            #endif
            guard let supabaseService else { return }
            await supabaseService.observeAuthStateChanges(using: authStateManager)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
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
                        subscriptionManager: subscriptionManager
                    )
                } catch {
                    noticeMessage = "Purchased slots could not sync: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: authStateManager.authState) { _, authState in
            if authState == .unauthenticated {
                navigationManager.resetAccountContext()
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
            updateWidgetAccount(userID)
            guard let userID else { return }
            let transactions = AccountScope.visibleTransactions(
                localTransactions, goals: localGoals, userID: userID
            )
            Task {
                guard authStateManager.userID == userID else { return }
                do {
                    try await storeKitManager.restorePurchasedSlots(
                        userID: userID,
                        modelContext: modelContext,
                        subscriptionManager: subscriptionManager
                    )
                } catch {
                    noticeMessage = "Purchased slots could not sync: \(error.localizedDescription)"
                }

                guard authStateManager.userID == userID,
                      let supabaseService,
                      !transactions.isEmpty else { return }
                do {
                    try await supabaseService.syncTransactions(transactions)
                } catch {
                    guard authStateManager.userID == userID else { return }
                    noticeMessage = "Signed in, but local savings could not sync: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: storeKitManager.lastSyncError) { _, error in
            if let error {
                noticeMessage = "Purchased slots were saved locally, but profile sync failed: \(error)"
            }
        }
        .onOpenURL { url in
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

            guard
                let supabaseService,
                url.scheme == supabaseService.configuration.redirectURL.scheme
            else {
                return
            }
            Task {
                do {
                    try await supabaseService.handleAuthCallback(
                        url,
                        authStateManager: authStateManager
                    )
                } catch {
                    noticeMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $navigationManager.isMilestonePresented) {
            ConsistencyMilestoneView(
                xpEarned: navigationManager.milestoneXPEarned,
                streakDays: navigationManager.milestoneStreakDays,
                onViewAchievements: {
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
            onForgotPassword: {
                noticeMessage = "Password reset is not configured yet."
            }
        )
    }

    private var dashboardView: some View {
        DashboardView(
            onCreateGoal: {
                choosingPlan = true
            },
            onSavingCompleted: { transaction, goal, xpEarned, streakDays in
                guard let userID = authStateManager.userID,
                      AccountScope.owns(goal, userID: userID),
                      transaction.userID == userID else { return }
                navigationManager.transactionDidComplete(
                    xpEarned: xpEarned,
                    streakDays: streakDays
                )
                guard let supabaseService else { return }
                Task {
                    guard authStateManager.userID == userID else { return }
                    do {
                        try await supabaseService.syncTransactions([transaction])
                    } catch {
                        guard authStateManager.userID == userID else { return }
                        noticeMessage = "Saved locally, but transaction sync failed: \(error.localizedDescription)"
                        return
                    }

                    guard authStateManager.userID == userID, goal.isGroupGoal else {
                        return
                    }
                    do {
                        try await supabaseService.broadcastGroupGoalProgress(
                            goalID: goal.id,
                            currentAmount: goal.currentAmount,
                            targetAmount: goal.targetAmount
                        )
                    } catch {
                        guard authStateManager.userID == userID else { return }
                        noticeMessage = "Transaction synced, but group progress could not update: \(error.localizedDescription)"
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

    private func clearWidgetSnapshot() {
        updateWidgetAccount(nil)
    }

    private func updateWidgetAccount(_ userID: UUID?) {
        do {
            try WidgetSharedData.activate(userID: userID)
            if userID == nil {
                try WidgetSharedData.save(.empty)
            }
        } catch {
            noticeMessage = "Widget account data could not be updated: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
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
                onViewAchievements: {
                    navigationManager.popToRoot()
                }
            )
        case .paywall(let isGroup):
            PaywallView(isGroup: isGroup)
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
