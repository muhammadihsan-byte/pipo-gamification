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
        let args = ProcessInfo.processInfo.arguments
        let qaInMemory = args.contains("-pipo-visual-qa")
            || args.contains("-pipo-account-qa")
            || args.contains("-pipo-onboarding-qa")
            || args.contains("-pipo-onboarding-qa-returning")
            || args.contains("-pipo-dashboard-qa")
        #else
        let qaInMemory = false
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: qaInMemory
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            #if DEBUG
            if args.contains("-pipo-dashboard-qa") {
                PipoDashboardQA.seed(in: container)
            }
            #endif
            return container
        } catch {
            fatalError("Failed to create the local data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-pipo-visual-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-account-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa")
                || ProcessInfo.processInfo.arguments.contains("-pipo-onboarding-qa-returning")
                || ProcessInfo.processInfo.arguments.contains("-pipo-dashboard-qa") {
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


#if DEBUG
/// Simulator-only fixtures. The production database and accounts are untouched.
@MainActor
private enum PipoDashboardQA {
    static func seed(in container: ModelContainer) {
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = Date.now
        let qaOwnerID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        func shifted(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: today) ?? today
        }

        let bali = PersonalGoal(
            title: "Bali holiday",
            category: .trip,
            targetAmount: 6_000_000,
            currentAmount: 3_600_000,
            startDate: shifted(-35),
            targetDate: shifted(80),
            rhythm: .weekly,
            preferredSavingDay: calendar.component(.weekday, from: today),
            ownerUserID: qaOwnerID,
            createdAt: shifted(-35)
        )
        bali.plannedContributionOverride = 75_000
        // DEBUG-only, in-memory example to validate the native Budget B
        // surface using real model rows (never user data or cloud writes).
        bali.subItems = [
            SubItem(title: "Travel & stay", amount: 3_500_000),
            SubItem(title: "Experiences", amount: 1_500_000),
            SubItem(title: "Documents", amount: 1_000_000)
        ]
        let ipad = PersonalGoal(
            title: "New iPad",
            category: .gadget,
            targetAmount: 5_000_000,
            currentAmount: 1_250_000,
            startDate: shifted(-25),
            targetDate: shifted(140),
            rhythm: .monthly,
            ownerUserID: qaOwnerID,
            createdAt: shifted(-25)
        )
        let group = PersonalGoal(
            title: "Bandung trip",
            category: .trip,
            targetAmount: 6_000_000,
            currentAmount: 4_200_000,
            startDate: shifted(-40),
            targetDate: shifted(120),
            rhythm: .flexible,
            isGroupGoal: true,
            ownerUserID: qaOwnerID,
            createdAt: shifted(-40)
        )

        [bali, ipad, group].forEach(context.insert)
        [shifted(-15), shifted(-8), shifted(-1)].forEach { date in
            context.insert(SavingTransaction(
                goalId: bali.id,
                amount: 75_000,
                date: date,
                userID: qaOwnerID
            ))
        }
        context.insert(UserProfile(
            userID: qaOwnerID,
            totalXP: 900,
            currentLevel: 1,
            streakDays: 3,
            unlockedBadgeIds: ["first-save", "plan-match", "quarter-way"]
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Pipo Dashboard QA fixture failed: \(error)")
        }
    }
}
#endif
