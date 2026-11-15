import Foundation
import Observation
import StoreKit
import SwiftData

enum StoreKitManagerError: LocalizedError {
    case productUnavailable
    case unverifiedPurchase(String)
    case unexpectedProduct(String)
    case missingPurchaseContext
    case transactionAccountMismatch

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "The goal slot is currently unavailable. Please try again later."
        case let .unverifiedPurchase(reason):
            "Apple could not verify this purchase: \(reason)"
        case let .unexpectedProduct(productID):
            "The purchase returned an unexpected product: \(productID)"
        case .missingPurchaseContext:
            "The pending purchase could not be matched to a goal type. Contact support before retrying."
        case .transactionAccountMismatch:
            "The purchase belongs to a different Satu Saku account."
        }
    }
}

@MainActor
@Observable
final class StoreKitManager {
    static let goalSlotProductID = "com.satusaku.goalslot"

    private(set) var slotProduct: Product?
    private(set) var isLoadingProduct = false
    private(set) var isPurchasing = false
    private(set) var hasPendingPurchase = false
    private(set) var productError: String?
    private(set) var purchaseStatusMessage: String?
    private(set) var lastSyncError: String?
    private(set) var lastCompletedTransactionID: UInt64?

    @ObservationIgnored private let supabaseService: SupabaseService?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    private let pendingPurchaseExistsKey = "storekit.goal-slot.pending"
    private let pendingPurchaseUserIDKey = "storekit.goal-slot.pending-user-id"
    private let pendingPurchaseGroupKey = "storekit.goal-slot.pending-is-group"

    init(
        supabaseService: SupabaseService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.supabaseService = supabaseService
        self.defaults = defaults
        hasPendingPurchase = defaults.bool(forKey: pendingPurchaseExistsKey)
        if hasPendingPurchase {
            purchaseStatusMessage = "Your previous purchase is still pending with Apple."
        }
    }

    func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [Self.goalSlotProductID])
            guard let product = products.first(where: { $0.id == Self.goalSlotProductID }) else {
                throw StoreKitManagerError.productUnavailable
            }
            slotProduct = product
            productError = nil
        } catch {
            slotProduct = nil
            productError = error.localizedDescription
        }
    }

    func purchaseSlot(
        isGroup: Bool,
        userID: UUID,
        modelContext: ModelContext,
        subscriptionManager: SubscriptionManager
    ) async throws -> Bool {
        guard !isPurchasing else { return false }
        guard !hasPendingPurchase else {
            purchaseStatusMessage = "Your previous purchase is still pending with Apple."
            return false
        }

        isPurchasing = true
        purchaseStatusMessage = nil
        lastSyncError = nil
        defer { isPurchasing = false }

        setPendingPurchase(userID: userID, isGroup: isGroup)

        if slotProduct == nil {
            await loadProduct()
        }
        guard let slotProduct else {
            clearPendingPurchase()
            throw StoreKitManagerError.productUnavailable
        }

        let result: Product.PurchaseResult
        do {
            result = try await slotProduct.purchase(options: [.appAccountToken(userID)])
        } catch {
            clearPendingPurchase()
            throw error
        }

        switch result {
        case let .success(verification):
            let transaction = try Self.verifiedTransaction(from: verification)
            guard transaction.productID == Self.goalSlotProductID else {
                throw StoreKitManagerError.unexpectedProduct(transaction.productID)
            }
            if let transactionUserID = transaction.appAccountToken, transactionUserID != userID {
                throw StoreKitManagerError.transactionAccountMismatch
            }
            try await applyVerifiedTransaction(
                transaction,
                isGroup: isGroup,
                userID: userID,
                modelContext: modelContext,
                subscriptionManager: subscriptionManager
            )
            purchaseStatusMessage = nil
            return true

        case .pending:
            purchaseStatusMessage = "Purchase pending approval. This slot will be added when Apple confirms it."
            return false

        case .userCancelled:
            clearPendingPurchase()
            return false

        @unknown default:
            clearPendingPurchase()
            throw StoreKitManagerError.productUnavailable
        }
    }

    func startTransactionUpdates(
        modelContext: ModelContext,
        subscriptionManager: SubscriptionManager,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                do {
                    let transaction = try Self.verifiedTransaction(from: verification)
                    guard transaction.productID == Self.goalSlotProductID else { continue }

                    let pending = self.pendingPurchaseContext
                    if let transactionUserID = transaction.appAccountToken,
                       try self.hasProcessed(
                           transactionID: transaction.id,
                           userID: transactionUserID,
                           modelContext: modelContext
                       ) {
                        await transaction.finish()
                        if pending?.userID == transactionUserID {
                            self.clearPendingPurchase()
                        }
                        continue
                    }

                    guard let pending else {
                        throw StoreKitManagerError.missingPurchaseContext
                    }
                    if let transactionUserID = transaction.appAccountToken,
                       transactionUserID != pending.userID {
                        throw StoreKitManagerError.transactionAccountMismatch
                    }
                    try await self.applyVerifiedTransaction(
                        transaction,
                        isGroup: pending.isGroup,
                        userID: transaction.appAccountToken ?? pending.userID,
                        modelContext: modelContext,
                        subscriptionManager: subscriptionManager
                    )
                } catch {
                    onError(error)
                }
            }
        }
    }

    func restorePurchasedSlots(
        userID: UUID,
        modelContext: ModelContext,
        subscriptionManager: SubscriptionManager
    ) async throws {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        var profile = UserProfile.existing(for: userID, in: profiles)
        if let profile {
            if profile.userID == nil {
                profile.userID = userID
                try modelContext.save()
            }
            subscriptionManager.updateEntitlements(
                purchasedPersonalSlots: profile.purchasedPersonalSlots,
                purchasedGroupSlots: profile.purchasedGroupSlots
            )
        } else {
            subscriptionManager.updateEntitlements(
                purchasedPersonalSlots: 0,
                purchasedGroupSlots: 0
            )
        }

        guard let supabaseService else { return }
        let remoteProfile = try await supabaseService.fetchUserProfileSlots(userID: userID)
        guard let remoteProfile else {
            if let profile {
                try await supabaseService.syncUserProfile(slotBalance(for: profile, userID: userID))
            }
            return
        }

        var didCreateProfile = false
        if profile == nil {
            let newProfile = UserProfile(userID: userID)
            modelContext.insert(newProfile)
            profile = newProfile
            didCreateProfile = true
        }
        guard let profile else { return }

        let personalSlots = max(profile.purchasedPersonalSlots, remoteProfile.purchasedPersonalSlots)
        let groupSlots = max(profile.purchasedGroupSlots, remoteProfile.purchasedGroupSlots)
        let needsSave = didCreateProfile
            || profile.userID != userID
            || profile.purchasedPersonalSlots != personalSlots
            || profile.purchasedGroupSlots != groupSlots
        profile.userID = userID
        profile.purchasedPersonalSlots = personalSlots
        profile.purchasedGroupSlots = groupSlots
        if needsSave {
            try modelContext.save()
        }
        subscriptionManager.updateEntitlements(
            purchasedPersonalSlots: personalSlots,
            purchasedGroupSlots: groupSlots
        )

        let mergedProfile = slotBalance(for: profile, userID: userID)
        if mergedProfile != remoteProfile {
            try await supabaseService.syncUserProfile(mergedProfile)
        }
    }

    func recordVerifiedSlotPurchase(
        transactionID: UInt64,
        isGroup: Bool,
        userID: UUID,
        modelContext: ModelContext,
        subscriptionManager: SubscriptionManager
    ) throws -> Bool {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let existingProfile = UserProfile.existing(for: userID, in: profiles)
        let profile = existingProfile ?? UserProfile(userID: userID)
        let isNewProfile = existingProfile == nil
        if isNewProfile {
            modelContext.insert(profile)
        }

        let transactionIDString = String(transactionID)
        if profile.processedStoreKitTransactionIDs.contains(transactionIDString) {
            subscriptionManager.updateEntitlements(
                purchasedPersonalSlots: profile.purchasedPersonalSlots,
                purchasedGroupSlots: profile.purchasedGroupSlots
            )
            return false
        }

        let oldUserID = profile.userID
        let oldPersonalSlots = profile.purchasedPersonalSlots
        let oldGroupSlots = profile.purchasedGroupSlots
        let oldTransactionIDs = profile.processedStoreKitTransactionIDs
        profile.userID = userID
        if isGroup {
            profile.purchasedGroupSlots += 1
        } else {
            profile.purchasedPersonalSlots += 1
        }
        profile.processedStoreKitTransactionIDs.append(transactionIDString)

        do {
            try modelContext.save()
        } catch {
            profile.userID = oldUserID
            profile.purchasedPersonalSlots = oldPersonalSlots
            profile.purchasedGroupSlots = oldGroupSlots
            profile.processedStoreKitTransactionIDs = oldTransactionIDs
            if isNewProfile {
                modelContext.delete(profile)
            }
            throw error
        }

        subscriptionManager.updateEntitlements(
            purchasedPersonalSlots: profile.purchasedPersonalSlots,
            purchasedGroupSlots: profile.purchasedGroupSlots
        )
        scheduleProfileSync(slotBalance(for: profile, userID: userID))
        return true
    }

    private func applyVerifiedTransaction(
        _ transaction: Transaction,
        isGroup: Bool,
        userID: UUID,
        modelContext: ModelContext,
        subscriptionManager: SubscriptionManager
    ) async throws {
        _ = try recordVerifiedSlotPurchase(
            transactionID: transaction.id,
            isGroup: isGroup,
            userID: userID,
            modelContext: modelContext,
            subscriptionManager: subscriptionManager
        )
        await transaction.finish()
        clearPendingPurchase()
        purchaseStatusMessage = nil
        lastCompletedTransactionID = transaction.id
    }

    private func hasProcessed(
        transactionID: UInt64,
        userID: UUID,
        modelContext: ModelContext
    ) throws -> Bool {
        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        guard let profile = profiles.first(where: { $0.userID == userID }) else {
            return false
        }
        return profile.processedStoreKitTransactionIDs.contains(String(transactionID))
    }

    private func slotBalance(
        for profile: UserProfile,
        userID: UUID
    ) -> UserProfileSlotBalancePayload {
        UserProfileSlotBalancePayload(
            userID: userID,
            purchasedPersonalSlots: profile.purchasedPersonalSlots,
            purchasedGroupSlots: profile.purchasedGroupSlots
        )
    }

    private func scheduleProfileSync(_ profile: UserProfileSlotBalancePayload) {
        guard let supabaseService else { return }
        Task { [weak self] in
            do {
                try await supabaseService.syncUserProfile(profile)
            } catch {
                self?.lastSyncError = error.localizedDescription
            }
        }
    }

    private var pendingPurchaseContext: (userID: UUID, isGroup: Bool)? {
        guard
            defaults.bool(forKey: pendingPurchaseExistsKey),
            let rawUserID = defaults.string(forKey: pendingPurchaseUserIDKey),
            let userID = UUID(uuidString: rawUserID),
            let isGroup = defaults.object(forKey: pendingPurchaseGroupKey) as? Bool
        else {
            return nil
        }
        return (userID, isGroup)
    }

    private func setPendingPurchase(userID: UUID, isGroup: Bool) {
        defaults.set(userID.uuidString, forKey: pendingPurchaseUserIDKey)
        defaults.set(isGroup, forKey: pendingPurchaseGroupKey)
        defaults.set(true, forKey: pendingPurchaseExistsKey)
        hasPendingPurchase = true
    }

    private func clearPendingPurchase() {
        defaults.removeObject(forKey: pendingPurchaseUserIDKey)
        defaults.removeObject(forKey: pendingPurchaseGroupKey)
        defaults.set(false, forKey: pendingPurchaseExistsKey)
        hasPendingPurchase = false
    }

    private static func verifiedTransaction(
        from verification: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch verification {
        case let .verified(transaction):
            return transaction
        case let .unverified(_, error):
            throw StoreKitManagerError.unverifiedPurchase(error.localizedDescription)
        }
    }
}
