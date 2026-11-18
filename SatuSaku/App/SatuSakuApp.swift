import SwiftData
import SwiftUI

@main
@MainActor
struct SatuSakuApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            PersonalGoal.self,
            SubItem.self,
            SavingTransaction.self,
            UserProfile.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the local data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-pipoButtonDemo") {
                PipoButtonDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("-pipoHomeDemo") {
                RootView(initialAuthState: .authenticated)
            } else {
                RootView()
            }
        }
        .modelContainer(modelContainer)
    }
}

private struct PipoButtonDemoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pipo Primary Button")
                    .font(.title2.bold())
                    .foregroundStyle(PipoColors.textPrimary)

                PipoPrimaryButton("Sign In Now", action: {})
                PipoPrimaryButton("Signing in…", state: .loading, isLoading: true, action: {})
                PipoPrimaryButton("Sign In Now", state: .disabled, action: {})

                PipoPrimaryButton("Keyboard Focus", state: .focus, action: {})
            }
            .padding(24)
        }
        .background(PipoColors.backgroundBase)
        .navigationTitle("Pipo Button Demo")
    }
}
