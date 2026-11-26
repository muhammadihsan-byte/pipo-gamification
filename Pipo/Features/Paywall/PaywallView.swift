import SwiftData
import SwiftUI

@MainActor
struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(StoreKitManager.self) private var storeKitManager
    @Environment(AuthStateManager.self) private var authStateManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let isGroup: Bool

    @State private var purchaseError: String?

    var body: some View {
        VStack(spacing: 18) {
            mascot

            Text("One more goal slot")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PipoTheme.ink)
            Text(StoreKitManager.purchasesEnabled
                 ? "You’ve used your free \(isGroup ? "group" : "personal") goal slot. You can unlock another with an Apple-verified purchase."
                 : "You’ve reached the free \(isGroup ? "group" : "personal") goal limit. Extra slots aren’t available yet. No payment will be taken; your existing goals are safe.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.muted)
                .padding(.horizontal, 12)

            if StoreKitManager.purchasesEnabled {
                Button {
                    purchaseGoalSlot()
                } label: {
                    Label(purchaseButtonTitle, systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(
                    storeKitManager.isPurchasing
                        || storeKitManager.isLoadingProduct
                        || storeKitManager.hasPendingPurchase
                )

                if storeKitManager.isPurchasing || storeKitManager.isLoadingProduct {
                    ProgressView()
                }
                if let message = storeKitManager.purchaseStatusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.muted)
                        .multilineTextAlignment(.center)
                } else if let message = storeKitManager.productError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(PipoTheme.deepPink)
                        .multilineTextAlignment(.center)
                }
            }

            Button(StoreKitManager.purchasesEnabled ? "Cancel Plan" : "Back to my goals") {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PipoTheme.muted)
            .disabled(storeKitManager.isPurchasing)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .task {
            if StoreKitManager.purchasesEnabled && storeKitManager.slotProduct == nil {
                await storeKitManager.loadProduct()
            }
        }
        .onChange(of: storeKitManager.lastCompletedTransactionID) { _, transactionID in
            if transactionID != nil {
                dismiss()
            }
        }
        .alert(
            "Purchase unavailable",
            isPresented: Binding(
                get: { purchaseError != nil },
                set: { if !$0 { purchaseError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                purchaseError = nil
            }
        } message: {
            Text(purchaseError ?? "")
        }
    }

    private var purchaseButtonTitle: String {
        guard let product = storeKitManager.slotProduct else {
            return "Load $2 slot price"
        }
        return "\(product.displayPrice) for permanent +1 slot"
    }

    private var mascot: some View {
        ZStack {
            PipoMascotView(companion: .reassurance)
                .frame(height: 210)

            HStack {
                piggyBank
                Spacer()
                piggyBank
            }
            .padding(.horizontal, 8)
            .offset(y: 62)
        }
        .frame(height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pipo holding two piggy banks and asking for support")
    }

    private var piggyBank: some View {
        Text("🐷")
            .font(.system(size: 48))
            .padding(8)
            .background(.white, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(PipoTheme.palePink, lineWidth: 3)
            }
            .shadow(color: PipoTheme.ink.opacity(0.08), radius: 5, y: 2)
    }

    private func purchaseGoalSlot() {
        guard let userID = authStateManager.userID else {
            purchaseError = "Sign in before purchasing a goal slot."
            return
        }

        Task {
            do {
                let purchased = try await storeKitManager.purchaseSlot(
                    isGroup: isGroup,
                    userID: userID,
                    modelContext: modelContext,
                    subscriptionManager: subscriptionManager
                )
                if purchased {
                    dismiss()
                }
            } catch {
                purchaseError = error.localizedDescription
            }
        }
    }
}

#Preview {
    PaywallView(isGroup: false)
        .environment(AuthStateManager(initialState: .authenticated, userID: UUID()))
        .environment(SubscriptionManager())
        .environment(StoreKitManager())
        .modelContainer(
            for: [PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self],
            inMemory: true
        )
}
