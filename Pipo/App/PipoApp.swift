import SwiftData
import SwiftUI

@main
@MainActor
struct PipoApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            PersonalGoal.self,
            SubItem.self,
            SavingTransaction.self,
            UserProfile.self
        ])
        #if DEBUG
        let qaInMemory = ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
        #else
        let qaInMemory = false
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: qaInMemory
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the local data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa") {
                RootView(initialAuthState: .authenticated)
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
        .modelContainer(modelContainer)
    }
}
