import Foundation
import XCTest
@testable import SatuSaku

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
        XCTAssertEqual(configuration.redirectURL.absoluteString, "satusaku://login-callback")
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
