import Foundation
import SwiftData
import XCTest
@testable import Pipo

final class StoreKitManagerTests: XCTestCase {
    @MainActor
    func testLivePurchasesAreBlockedUntilServerVerificationExists() async throws {
        XCTAssertFalse(StoreKitManager.purchasesEnabled)
        let container = try makeContainer()
        let manager = StoreKitManager(defaults: try makeDefaults())
        let entitlements = SubscriptionManager()
        do {
            _ = try await manager.purchaseSlot(
                isGroup: false,
                userID: UUID(),
                modelContext: container.mainContext,
                subscriptionManager: entitlements
            )
            XCTFail("An unverified permanent slot must never charge a user.")
        } catch StoreKitManagerError.purchasesAwaitingServerVerification {
            XCTAssertEqual(entitlements.purchasedPersonalSlots, 0)
            XCTAssertFalse(manager.isPurchasing)
        } catch {
            XCTFail("Unexpected purchase error: \(error)")
        }
    }

    @MainActor
    func testVerifiedPurchaseAddsSlotToCorrectBalanceAndPersistsIt() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let userID = UUID()
        let manager = StoreKitManager(defaults: try makeDefaults())
        let subscriptionManager = SubscriptionManager()

        let wasApplied = try manager.recordVerifiedSlotPurchase(
            transactionID: 101,
            isGroup: true,
            userID: userID,
            modelContext: context,
            subscriptionManager: subscriptionManager
        )

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertTrue(wasApplied)
        XCTAssertEqual(profile.userID, userID)
        XCTAssertEqual(profile.purchasedPersonalSlots, 0)
        XCTAssertEqual(profile.purchasedGroupSlots, 1)
        XCTAssertEqual(subscriptionManager.purchasedGroupSlots, 1)
    }

    @MainActor
    func testReplayedStoreKitTransactionDoesNotGrantAnotherSlot() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let userID = UUID()
        let manager = StoreKitManager(defaults: try makeDefaults())
        let subscriptionManager = SubscriptionManager()

        _ = try manager.recordVerifiedSlotPurchase(
            transactionID: 202,
            isGroup: false,
            userID: userID,
            modelContext: context,
            subscriptionManager: subscriptionManager
        )
        let replayWasApplied = try manager.recordVerifiedSlotPurchase(
            transactionID: 202,
            isGroup: false,
            userID: userID,
            modelContext: context,
            subscriptionManager: subscriptionManager
        )

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertFalse(replayWasApplied)
        XCTAssertEqual(profile.purchasedPersonalSlots, 1)
        XCTAssertEqual(profile.processedStoreKitTransactionIDs, ["202"])
        XCTAssertEqual(subscriptionManager.purchasedPersonalSlots, 1)
    }

    @MainActor
    func testPurchasedSlotProfilesAreScopedToTheirAccount() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let manager = StoreKitManager(defaults: try makeDefaults())
        let subscriptionManager = SubscriptionManager()
        let firstUserID = UUID()
        let secondUserID = UUID()

        _ = try manager.recordVerifiedSlotPurchase(
            transactionID: 301,
            isGroup: false,
            userID: firstUserID,
            modelContext: context,
            subscriptionManager: subscriptionManager
        )
        _ = try manager.recordVerifiedSlotPurchase(
            transactionID: 302,
            isGroup: true,
            userID: secondUserID,
            modelContext: context,
            subscriptionManager: subscriptionManager
        )

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let firstProfile = try XCTUnwrap(profiles.first { $0.userID == firstUserID })
        let secondProfile = try XCTUnwrap(profiles.first { $0.userID == secondUserID })
        XCTAssertEqual(firstProfile.purchasedPersonalSlots, 1)
        XCTAssertEqual(firstProfile.purchasedGroupSlots, 0)
        XCTAssertEqual(secondProfile.purchasedPersonalSlots, 0)
        XCTAssertEqual(secondProfile.purchasedGroupSlots, 1)
    }


    @MainActor
    func testDeletedAccountClearsOnlyItsStoreKitPendingPurchaseContext() throws {
        let defaults = try makeDefaults()
        let deletedUser = UUID()
        let anotherUser = UUID()
        defaults.set(true, forKey: "storekit.goal-slot.pending")
        defaults.set(deletedUser.uuidString, forKey: "storekit.goal-slot.pending-user-id")
        defaults.set(false, forKey: "storekit.goal-slot.pending-is-group")

        let manager = StoreKitManager(defaults: defaults)
        XCTAssertTrue(manager.hasPendingPurchase)
        manager.discardDeletedAccountPurchaseContext(anotherUser)
        XCTAssertTrue(manager.hasPendingPurchase)
        XCTAssertEqual(defaults.string(forKey: "storekit.goal-slot.pending-user-id"),
                       deletedUser.uuidString)

        manager.discardDeletedAccountPurchaseContext(deletedUser)
        XCTAssertFalse(manager.hasPendingPurchase)
        XCTAssertNil(defaults.string(forKey: "storekit.goal-slot.pending-user-id"))
        XCTAssertFalse(defaults.bool(forKey: "storekit.goal-slot.pending"))
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    }
}
