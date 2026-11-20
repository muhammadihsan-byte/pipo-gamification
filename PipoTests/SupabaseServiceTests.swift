import Foundation
import XCTest
@testable import Pipo

final class SupabaseServiceTests: XCTestCase {
    func testLoadsSupabaseConfigurationFromEnvironmentAndInfoPlist() throws {
        let configuration = try SupabaseConfiguration.load(
            environment: ["SUPABASE_URL": "https://env.supabase.co"],
            infoDictionary: [
                "SUPABASE_URL": "https://plist.supabase.co",
                "SUPABASE_ANON_KEY": "public-anon-key"
            ]
        )

        XCTAssertEqual(configuration.url.absoluteString, "https://env.supabase.co")
        XCTAssertEqual(configuration.anonKey, "public-anon-key")
        XCTAssertEqual(configuration.redirectURL.absoluteString, "pipo://login-callback")
    }

    func testPasswordRecoveryCallbackRoutesAndSocialProvidersRemainGated() throws {
        let config = try SupabaseConfiguration.load(
            environment: [
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_ANON_KEY": "public-key"
            ], infoDictionary: [:]
        )
        XCTAssertEqual(
            config.passwordRecoveryRedirectURL.absoluteString,
            "pipo://login-callback/reset-password"
        )
        XCTAssertTrue(config.isSignInCallback(URL(string: "pipo://login-callback?code=abc")!))
        XCTAssertFalse(config.isPasswordRecoveryCallback(URL(string: "pipo://login-callback?code=abc")!))
        XCTAssertTrue(config.isPasswordRecoveryCallback(
            URL(string: "pipo://login-callback/reset-password?code=abc")!
        ))
        XCTAssertFalse(config.isSignInCallback(URL(string: "pipo://login-callback.evil?code=abc")!))
        XCTAssertFalse(config.isPasswordRecoveryCallback(
            URL(string: "pipo://another-host/reset-password?code=abc")!
        ))
        XCTAssertFalse(AuthProviderAvailability.socialSignInEnabled)
    }

    func testRejectsMissingOrInsecureSupabaseConfiguration() {
        XCTAssertThrowsError(
            try SupabaseConfiguration.load(environment: [:], infoDictionary: [:])
        )
        XCTAssertThrowsError(
            try SupabaseConfiguration.load(
                environment: [
                    "SUPABASE_URL": "http://remote.example.com",
                    "SUPABASE_ANON_KEY": "public-anon-key"
                ],
                infoDictionary: [:]
            )
        )
    }

    func testSavingTransactionPayloadUsesDatabaseColumnNames() throws {
        let payload = SavingTransactionPayload(
            id: UUID(),
            goalID: UUID(),
            userID: UUID(),
            amount: 125_000,
            xpEarned: 300,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(json.keys),
            ["id", "goal_id", "user_id", "amount", "xp_earned", "date"]
        )
        XCTAssertEqual(json["amount"] as? Double, 125_000)
        XCTAssertEqual(json["xp_earned"] as? Int, 300)
    }

    func testSavingTransactionBatchRejectsRowsOwnedByAnotherAccount() throws {
        let userID = UUID()
        let transaction = SavingTransaction(
            goalId: UUID(),
            amount: 125_000,
            userID: userID
        )
        let payloads = try SavingTransactionPayload.makeBatch(
            from: [transaction],
            authenticatedUserID: userID
        )

        XCTAssertEqual(payloads.map(\.userID), [userID])

        let otherUserTransaction = SavingTransaction(
            goalId: UUID(),
            amount: 50_000,
            userID: UUID()
        )
        XCTAssertThrowsError(
            try SavingTransactionPayload.makeBatch(
                from: [otherUserTransaction],
                authenticatedUserID: userID
            )
        )
    }


    @MainActor
    func testGoalFirstBatchUsesDeployedTableColumnsAndISODates() throws {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let goal = PersonalGoal(
            title: "Bali trip", category: .trip, targetAmount: 1_000_000,
            startDate: start, targetDate: start.addingTimeInterval(86400 * 21),
            rhythm: .weekly, preferredSavingDay: 3, ownerUserID: owner
        )
        goal.plannedContributionOverride = 200_000
        let tx = SavingTransaction(
            goalId: goal.id, amount: 200_000,
            date: start.addingTimeInterval(86400 * 7), userID: owner
        )
        let batch = try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [tx], authenticatedUserID: owner
        )
        XCTAssertEqual(batch.goals.count, 1)
        XCTAssertEqual(batch.transactions.count, 1)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(batch.goals[0]))
                as? [String: Any]
        )
        XCTAssertEqual(Set(json.keys), Set([
            "id", "user_id", "title", "category", "target_amount",
            "start_date", "target_date", "rhythm", "preferred_saving_day",
            "planned_contribution_override"
        ]))
        XCTAssertEqual(json["user_id"] as? String, owner.uuidString)
        XCTAssertEqual(json["rhythm"] as? String, "weekly")
        XCTAssertTrue((json["start_date"] as? String)?.contains("T") == true)
        XCTAssertTrue((json["target_date"] as? String)?.hasSuffix("Z") == true)

        let txJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(batch.transactions[0]))
                as? [String: Any]
        )
        XCTAssertEqual(txJSON["goal_id"] as? String, goal.id.uuidString)
        XCTAssertTrue((txJSON["date"] as? String)?.hasSuffix("Z") == true)
    }

    @MainActor
    func testSyncBatchRejectsCrossAccountAndOwnerlessGoals() throws {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 500_000,
            startDate: start, targetDate: start.addingTimeInterval(86400 * 10),
            ownerUserID: owner
        )
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [], authenticatedUserID: UUID()
        ))
        goal.ownerUserID = nil
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [], authenticatedUserID: owner
        ))
    }

    @MainActor
    func testSyncBatchRejectsGroupPlansAndOrphanOrForeignTransactions() throws {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 500_000,
            startDate: start, targetDate: start.addingTimeInterval(86400 * 10),
            isGroupGoal: true, ownerUserID: owner
        )
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [], authenticatedUserID: owner
        ))
        goal.isGroupGoal = false
        let otherGoalTransaction = SavingTransaction(
            goalId: UUID(), amount: 50_000, userID: owner
        )
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [otherGoalTransaction],
            authenticatedUserID: owner
        ))
        let crossAccountTransaction = SavingTransaction(
            goalId: goal.id, amount: 50_000, userID: UUID()
        )
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [crossAccountTransaction],
            authenticatedUserID: owner
        ))
    }

    @MainActor
    func testSyncBatchRejectsInvalidGoalAndAmounts() throws {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let goal = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 200_000,
            startDate: start, targetDate: start.addingTimeInterval(86400 * 2),
            ownerUserID: owner
        )
        goal.targetAmount = .infinity
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [], authenticatedUserID: owner
        ))
        goal.targetAmount = 200_000
        let negative = SavingTransaction(
            goalId: goal.id, amount: -1, userID: owner
        )
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: [goal], transactions: [negative], authenticatedUserID: owner
        ))
    }

    func testGroupProgressPayloadUsesStableRealtimeFieldNames() throws {
        let update = GroupGoalProgressUpdate(
            goalID: UUID(),
            userID: UUID(),
            currentAmount: 450_000,
            targetAmount: 1_000_000,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(json.keys),
            ["goal_id", "user_id", "current_amount", "target_amount", "updated_at"]
        )
        XCTAssertEqual(json["current_amount"] as? Double, 450_000)
        XCTAssertEqual(json["target_amount"] as? Double, 1_000_000)
    }

    func testUserProfileSlotPayloadUsesScopedDatabaseColumns() throws {
        let userID = UUID()
        let payload = UserProfileSlotBalancePayload(
            userID: userID,
            purchasedPersonalSlots: 2,
            purchasedGroupSlots: 1
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(json.keys),
            ["user_id", "purchased_personal_slots", "purchased_group_slots"]
        )
        XCTAssertEqual(json["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(json["purchased_personal_slots"] as? Int, 2)
        XCTAssertEqual(json["purchased_group_slots"] as? Int, 1)
    }
}
