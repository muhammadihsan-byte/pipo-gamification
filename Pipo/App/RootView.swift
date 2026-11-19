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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboardingCompletion: OnboardingCompletion?
    @State private var isPrefillingOnboardingGoal = false
    @Environment(\.modelContext) private var modelContext
    @Query private var localTransactions: [SavingTransaction]

    private let supabaseConfigurationError: String?

    init(
        initialAuthState: AuthState = .unauthenticated,
        initialRoute: Route? = nil
    ) {
        _navigationManager = State(
            initialValue: NavigationManager(initialRoute: initialRoute)
        )
        _authStateManager = State(
            initialValue: AuthStateManager(initialState: initialAuthState)
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
            guard let supabaseService else { return }
            await supabaseService.observeAuthStateChanges(using: authStateManager)
        }
        .task {
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
                navigationManager.popToRoot()
                clearWidgetSnapshot()
            } else {
                navigationManager.popToRoot()
                if let onboardingCompletion {
                    routeAfterOnboarding(completion: onboardingCompletion)
                }
            }
        }
        .onChange(of: authStateManager.userID) { _, userID in
            guard let userID else { return }
            let transactions = localTransactions.filter { $0.userID == userID }
            Task {
                do {
                    try await storeKitManager.restorePurchasedSlots(
                        userID: userID,
                        modelContext: modelContext,
                        subscriptionManager: subscriptionManager
                    )
                } catch {
                    noticeMessage = "Purchased slots could not sync: \(error.localizedDescription)"
                }

                guard let supabaseService, !transactions.isEmpty else { return }
                do {
                    try await supabaseService.syncTransactions(transactions)
                } catch {
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
            if hasCompletedOnboarding {
                authenticationView
            } else {
                onboardingView
            }
        case .authenticated:
            dashboardView
        }
    }

    private var onboardingView: some View {
        OnboardingContainerView(
            onCompleted: { completion in
                onboardingCompletion = completion
                hasCompletedOnboarding = true
                if authStateManager.authState == .authenticated {
                    routeAfterOnboarding(completion: completion)
                }
            },
            onSignIn: {
                hasCompletedOnboarding = true
            }
        )
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
                navigationManager.transactionDidComplete(
                    xpEarned: xpEarned,
                    streakDays: streakDays
                )
                guard let supabaseService else { return }
                Task {
                    do {
                        try await supabaseService.syncTransactions([transaction])
                    } catch {
                        noticeMessage = "Saved locally, but transaction sync failed: \(error.localizedDescription)"
                        return
                    }

                    guard goal.isGroupGoal else {
                        return
                    }
                    do {
                        try await supabaseService.broadcastGroupGoalProgress(
                            goalID: goal.id,
                            currentAmount: goal.currentAmount,
                            targetAmount: goal.targetAmount
                        )
                    } catch {
                        noticeMessage = "Transaction synced, but group progress could not update: \(error.localizedDescription)"
                    }
                }
            }
        )
        .confirmationDialog("Choose a saving plan", isPresented: $choosingPlan, titleVisibility: .visible) {
            Button("Personal saving") { navigationManager.navigate(to: .createGoal) }
            Button("Group saving") { navigationManager.navigate(to: .reviewGroupSaving) }
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
        do {
            try WidgetSharedData.save(.empty)
        } catch {
            noticeMessage = "Widget data could not be cleared: \(error.localizedDescription)"
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
                onBack: {
                    isPrefillingOnboardingGoal = false
                    onboardingCompletion = nil
                    navigationManager.pop()
                },
                onCreated: { goalID in
                    isPrefillingOnboardingGoal = false
                    onboardingCompletion = nil
                    navigationManager.popToRoot()
                    navigationManager.navigate(to: .personalGoal(goalID))
                },
                initialTitle: isPrefillingOnboardingGoal
                    ? (onboardingCompletion?.goalTitle ?? "")
                    : "",
                initialCategory: isPrefillingOnboardingGoal
                    ? (onboardingCompletion?.goalCategory ?? .gadget)
                    : .gadget,
                initialRhythm: isPrefillingOnboardingGoal
                    ? (onboardingCompletion?.rhythm ?? .monthly)
                    : .monthly
            )
        case .personalGoal(let goalID):
            PersonalGoalDetailView(goalID: goalID, onBack: navigationManager.pop) {
                navigationManager.requestDeposit(goalID: goalID)
            }
        case .savingRhythm, .reviewGroupSaving:
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

    private func routeAfterOnboarding(completion: OnboardingCompletion) {
        guard authStateManager.authState == .authenticated else { return }
        if completion.isPlusSelected {
            navigationManager.navigate(to: .paywall(isGroup: completion.isGroupSaving))
            onboardingCompletion = nil
        } else if completion.isGroupSaving {
            onboardingCompletion = nil
            navigationManager.navigate(to: .reviewGroupSaving)
        } else if completion.goalCategory != nil, completion.goalTitle != nil {
            isPrefillingOnboardingGoal = true
            navigationManager.navigate(to: .createGoal)
        } else {
            navigationManager.popToRoot()
            onboardingCompletion = nil
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
            RootView(initialAuthState: .authenticated, initialRoute: .savingRhythm)
                .previewDisplayName("Saving Rhythm")
            RootView(initialAuthState: .authenticated, initialRoute: .reviewGroupSaving)
                .previewDisplayName("Group Review")
            RootView(initialAuthState: .authenticated, initialRoute: .milestoneCelebration)
                .previewDisplayName("Milestone")
        }
        .modelContainer(
            for: [PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self],
            inMemory: true
        )
    }
}
