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
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
