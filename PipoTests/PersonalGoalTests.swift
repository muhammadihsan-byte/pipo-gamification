import Foundation
import UIKit
import SwiftUI
import SwiftData
import XCTest
@testable import Pipo

final class PersonalGoalTests: XCTestCase {

    #if PIPO_ISSUE80_STAGING
    /// Deferred native QA. Linux does not have SwiftData; run when the owner
    /// re-enables Mac runner and the staging flag is intentionally activated.
    @MainActor
    func testIssue80PersistedFirstGoalReconcilesWithoutChangingSavingOrXP() throws {
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pipo-issue80-native-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = ModelConfiguration(
            schema: schema, url: folder.appendingPathComponent("goal.store")
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let writer = ModelContext(container)
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let target = Date(timeIntervalSince1970: 1_810_000_000)

        let safe = PersonalGoal(
            title: "Camera", category: .gadget, targetAmount: 0.30,
            currencyCode: "USD", targetMinorUnits: 30, recordedMinorUnits: 0,
            startDate: start, targetDate: target, rhythm: .weekly,
            preferredSavingDay: 2, ownerUserID: owner
        )
        let unsafe = PersonalGoal(
            title: "Trip", category: .trip, targetAmount: 1,
            currentAmount: 0.01, currencyCode: "USD",
            targetMinorUnits: 100, recordedMinorUnits: 1,
            startDate: start, targetDate: target, rhythm: .weekly,
            preferredSavingDay: 2, ownerUserID: owner
        )
        unsafe.subItems = [
            SubItem(title: "Hotel", amount: 1, amountMinorUnits: 100)
        ]
        let saving = SavingTransaction(
            goalId: unsafe.id, amount: 0.01, amountMinorUnits: 1,
            currencyCode: "USD", xpEarned: 7, userID: owner
        )
        let profile = UserProfile(userID: owner, totalXP: 41)
        writer.insert(safe)
        writer.insert(unsafe)
        writer.insert(saving)
        writer.insert(profile)
        try writer.save()

        let journal = SavingGoalCreateIntentJournal(
            directory: folder.appendingPathComponent("pending")
        )
        func request(for goal: PersonalGoal, minor: Int64)
            throws -> SavingGoalCreateOnlyRequest {
            try SavingGoalCreateOnlyRequest(
                goalID: goal.id, ownerID: owner, title: goal.title,
                category: goal.category.rawValue, customCategory: nil,
                targetMinorUnits: minor, currencyCode: "USD",
                startDate: start, targetDate: target, rhythm: "weekly",
                preferredSavingDay: 2, plannedContributionMinorUnits: nil
            )
        }
        func verified(_ request: SavingGoalCreateOnlyRequest) throws {
            try journal.stage(request, ownerID: owner)
            // JSONSerialization bridges JSON decimals through NSNumber,
            // potentially changing USD cents (0.30) into floating-point
            // approximations on Apple Foundation. Inject only the simulated
            // server-owned keys into the original exact JSONEncoder bytes.
            let wire = String(decoding: try JSONEncoder().encode(request),
                              as: UTF8.self)
            XCTAssertTrue(wire.hasPrefix("{"))
            let ownedRow = "{\"user_id\":\"\\(owner.uuidString)\",\"plan_revision\":0,"
                + String(wire.dropFirst())
            let server = try JSONDecoder().decode(
                SavingGoalAuthoritativeCloudRow.self,
                from: Data(ownedRow.utf8)
            )
            XCTAssertEqual(server.targetAmount, request.targetAmount,
                           "Exact currency Decimal should survive a wire round trip")
            XCTAssertEqual(
                try journal.recordReadback(
                    server, goalID: request.goalID, ownerID: owner,
                    authenticatedOwnerID: owner
                ), .verified
            )
        }
        try verified(request(for: safe, minor: 30))
        try verified(request(for: unsafe, minor: 100))

        XCTAssertEqual(
            try SavingGoalCreateSwiftDataCommit.finalizePersistedGoal(
                goalID: safe.id, authenticatedOwnerID: owner,
                modelContainer: container, journal: journal
            ), .reconciled
        )
        XCTAssertEqual(try journal.pending(for: owner).count, 1)
        XCTAssertEqual(try journal.all(for: owner).count, 2)
        XCTAssertEqual(
            try SavingGoalCreateSwiftDataCommit.finalizePersistedGoal(
                goalID: safe.id, authenticatedOwnerID: owner,
                modelContainer: container, journal: journal
            ), .reconciled // Identical relaunch/replay cannot duplicate anything.
        )
        XCTAssertThrowsError(
            try SavingGoalCreateSwiftDataCommit.finalizePersistedGoal(
                goalID: unsafe.id, authenticatedOwnerID: owner,
                modelContainer: container, journal: journal
            )
        )

        let reopened = ModelContext(container)
        let persisted = try reopened.fetch(FetchDescriptor<PersonalGoal>())
        let savings = try reopened.fetch(FetchDescriptor<SavingTransaction>())
        let profiles = try reopened.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(savings.count, 1)
        XCTAssertEqual(savings[0].id, saving.id)
        XCTAssertEqual(savings[0].xpEarned, 7)
        XCTAssertEqual(profiles.first(where: { $0.userID == owner })?.totalXP, 41)
        XCTAssertEqual(persisted.first(where: { $0.id == safe.id })?.targetMinorUnits, 30)
        XCTAssertEqual(persisted.first(where: { $0.id == unsafe.id })?.recordedMinorUnits, 1)
        XCTAssertEqual(persisted.first(where: { $0.id == unsafe.id })?.subItems.count, 1)
    }
    #endif


    // These are intentionally dormant contract tests. They do not contact
    // Supabase or enable Manage Plan Save, and require iOS XCTest later.
    func testIssue80CASRequestUsesExactAmountsAndOnlyRPCParameters() throws {
        let owner = UUID(), goal = UUID(), id = UUID()
        let request = try SavingPlanCASRequest(
            requestID: id, goalID: goal, expectedRevision: 3,
            targetMinorUnits: 30, currencyCode: "USD",
            targetDate: Date(timeIntervalSince1970: 1_800_000_000),
            rhythm: "weekly", preferredSavingDay: 2,
            plannedContributionMinorUnits: 10
        )
        XCTAssertEqual(request.targetAmount, Decimal(string: "0.30"))
        XCTAssertEqual(request.plannedContributionOverride, Decimal(string: "0.10"))
        let encoded = try JSONEncoder().encode(request)
        let fields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(Set(fields.keys), Set([
            "p_request_id", "p_goal_id", "p_expected_revision",
            "p_target_amount", "p_target_date", "p_rhythm",
            "p_preferred_saving_day", "p_planned_contribution_override"
        ]))
        XCTAssertEqual(fields["p_goal_id"] as? String, goal.uuidString)
        XCTAssertEqual(fields["p_request_id"] as? String, id.uuidString)
        XCTAssertEqual(fields["p_expected_revision"] as? Int, 3)
        XCTAssertNil(fields["p_user_id"])
        XCTAssertNil(fields["p_currency_code"])
        XCTAssertNil(fields["currency_code"])
        _ = owner // Owner comes from auth.uid(), never app-submitted JSON.

        let flexible = try SavingPlanCASRequest(
            requestID: UUID(), goalID: goal, expectedRevision: 0,
            targetMinorUnits: 6_000_000, currencyCode: "IDR",
            targetDate: Date(timeIntervalSince1970: 1_800_000_000),
            rhythm: "flexible", preferredSavingDay: nil,
            plannedContributionMinorUnits: nil
        )
        let flexibleFields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(flexible))
                as? [String: Any]
        )
        XCTAssertTrue(flexibleFields["p_preferred_saving_day"] is NSNull)
        XCTAssertTrue(flexibleFields["p_planned_contribution_override"] is NSNull)
    }

    func testIssue80CASRejectsInvalidInputBeforeAnyBackendCall() throws {
        func request(revision: Int64 = 0, minor: Int64 = 6_000_000,
                     currency: String = "IDR", rhythm: String = "weekly",
                     day: Int? = 2, contribution: Int64? = nil) throws
            -> SavingPlanCASRequest {
            try SavingPlanCASRequest(
                requestID: UUID(), goalID: UUID(), expectedRevision: revision,
                targetMinorUnits: minor, currencyCode: currency,
                targetDate: Date(timeIntervalSince1970: 1_800_000_000),
                rhythm: rhythm, preferredSavingDay: day,
                plannedContributionMinorUnits: contribution
            )
        }
        XCTAssertThrowsError(try request(revision: -1))
        XCTAssertThrowsError(try request(revision: Int64.max))
        XCTAssertThrowsError(try request(minor: 0))
        XCTAssertThrowsError(try request(minor: Int64.max))
        XCTAssertThrowsError(try request(currency: "KWD"))
        XCTAssertThrowsError(try request(rhythm: "unexpected"))
        XCTAssertThrowsError(try request(rhythm: "weekly", day: 8))
        XCTAssertThrowsError(try request(rhythm: "flexible", day: 2))
        XCTAssertThrowsError(try request(rhythm: "flexible", day: nil, contribution: 20))
        XCTAssertThrowsError(try request(contribution: -1))
        XCTAssertNoThrow(try request(minor: 30, currency: "USD", contribution: 10))
    }

    func testIssue80CASReceiptVerifiesExactPayloadAndRejectsSpuriousSuccess() throws {
        let requestID = UUID(), goalID = UUID()
        let targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        let request = try SavingPlanCASRequest(
            requestID: requestID, goalID: goalID, expectedRevision: 0,
            targetMinorUnits: 30, currencyCode: "USD",
            targetDate: targetDate, rhythm: "weekly", preferredSavingDay: 2,
            plannedContributionMinorUnits: 10
        )
        func decode(_ raw: String) throws -> SavingPlanCASWireResponse {
            try JSONDecoder().decode(
                SavingPlanCASWireResponse.self, from: Data(raw.utf8)
            )
        }
        let applied = """
        {"status":"applied","request_id":"\(requestID.uuidString)",
         "goal_id":"\(goalID.uuidString)","currency_code":"USD",
         "accepted_revision":1,"target_amount":0.30,
         "target_date":"\(request.targetDate)","rhythm":"weekly",
         "preferred_saving_day":2,"planned_contribution_override":0.10}
        """
        XCTAssertEqual(
            try SavingPlanCASReceiptValidator.verify(decode(applied), for: request),
            .applied(requestID: requestID, acceptedRevision: 1)
        )
        // An idempotent replay reports the original receipt, not revision +2.
        XCTAssertEqual(
            try SavingPlanCASReceiptValidator.verify(decode(applied), for: request),
            .applied(requestID: requestID, acceptedRevision: 1)
        )
        let conflict = """
        {"status":"conflict","goal_id":"\(goalID.uuidString)",
         "current_revision":2}
        """
        XCTAssertEqual(
            try SavingPlanCASReceiptValidator.verify(decode(conflict), for: request),
            .conflict(currentRevision: 2)
        )
        let tamperedCurrency = applied.replacingOccurrences(
            of: "\"currency_code\":\"USD\"", with: "\"currency_code\":\"IDR\""
        )
        XCTAssertThrowsError(try SavingPlanCASReceiptValidator.verify(
            decode(tamperedCurrency), for: request
        ))
        let tamperedAmount = applied.replacingOccurrences(
            of: "\"target_amount\":0.30", with: "\"target_amount\":0.31"
        )
        XCTAssertThrowsError(try SavingPlanCASReceiptValidator.verify(
            decode(tamperedAmount), for: request
        ))
        let tamperedID = applied.replacingOccurrences(
            of: goalID.uuidString, with: UUID().uuidString
        )
        XCTAssertThrowsError(try SavingPlanCASReceiptValidator.verify(
            decode(tamperedID), for: request
        ))
        let tamperedRevision = applied.replacingOccurrences(
            of: "\"accepted_revision\":1", with: "\"accepted_revision\":99"
        )
        XCTAssertThrowsError(try SavingPlanCASReceiptValidator.verify(
            decode(tamperedRevision), for: request
        ))
        XCTAssertThrowsError(try SavingPlanCASReceiptValidator.verify(
            decode("{\"status\":\"applied\",\"goal_id\":\"\(goalID.uuidString)\"}"),
            for: request
        ))
    }


    /// Guard the actual SwiftUI Color tokens used as filled backgrounds behind
    /// white CTA text. WCAG AA normal-text threshold is 4.5:1. Do not test
    /// a duplicated hex value that could drift from the production button.
    @MainActor
    func testGlobalV1FilledPrimaryActionTextContrastMeetsWCAGAA() {
        let activeButtons: [(String, UIColor)] = [
            ("Create Goal", UIColor(PersonalPlanStyle.buttonEdge)),
            ("Manage Plan", UIColor(PipoTheme.cardAccentReadable))
        ]
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 :
                pow((value + 0.055) / 1.055, 2.4)
        }
        for (name, background) in activeButtons {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(background.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
                          name + " color must resolve to RGB")
            let luminance = 0.2126 * channel(Double(red))
                + 0.7152 * channel(Double(green))
                + 0.0722 * channel(Double(blue))
            let whiteTextContrast = 1.05 / (luminance + 0.05)
            XCTAssertGreaterThanOrEqual(whiteTextContrast, 4.5,
                name + " filled CTA white text does not meet normal-text AA")
        }
    }

    @MainActor
    func testGlobalV1ExactRemainingAndCompletionAvoidFloatingPointDrift() {
        let goal = PersonalGoal(
            title: "Small USD goal", category: .gadget,
            targetAmount: 0.30, currentAmount: 0.20,
            currencyCode: "USD", targetMinorUnits: 30,
            recordedMinorUnits: 20,
            targetDate: .now.addingTimeInterval(86_400),
            ownerUserID: UUID()
        )
        XCTAssertEqual(goal.exactRemainingMinor, 10)
        XCTAssertEqual(goal.remainingAmount, 0.10)
        XCTAssertEqual(goal.lifecycleState, .active)
        XCTAssertEqual(PipoGoalCurrency.formatted(goal.exactRemainingMinor!, code: "USD"),
                       PipoGoalCurrency.formatted(10, code: "USD"))

        // The Double cache must never complete a goal prematurely.
        goal.currentAmount = 0.30
        goal.recordedMinorUnits = 29
        XCTAssertEqual(goal.lifecycleState, .active)
        XCTAssertEqual(goal.exactRemainingMinor, 1)

        // Nor should a Double that under-represents 0.9 prevent completion.
        goal.targetAmount = 0.9
        goal.currentAmount = 0.6 + 0.3
        goal.targetMinorUnits = 90
        goal.recordedMinorUnits = 90
        XCTAssertEqual(goal.lifecycleState, .completed)
        XCTAssertEqual(goal.exactRemainingMinor, 0)
    }


    /// The next recorded saving must cause the full owner-scoped backlog to
    /// be replayed, not only the newest local transaction. UUID identities are
    /// stable across retries; another account's records never enter the batch.
    @MainActor
    func testGlobalV1ReconnectingWithNextSavingIncludesEarlierOfflineBacklog() throws {
        let alice = UUID(), bob = UUID()
        let aliceGoal = PersonalGoal(
            title: "Laptop", category: .gadget, targetAmount: 10,
            currentAmount: 0.03, currencyCode: "USD", targetMinorUnits: 1_000,
            recordedMinorUnits: 3,
            targetDate: .now.addingTimeInterval(86_400 * 40), ownerUserID: alice
        )
        let bobGoal = PersonalGoal(
            title: "Bob's trip", category: .trip, targetAmount: 500,
            currencyCode: "USD", targetMinorUnits: 50_000,
            targetDate: .now.addingTimeInterval(86_400 * 40), ownerUserID: bob
        )
        // First saving was recorded offline; second was made after reconnect.
        let offline = SavingTransaction(
            goalId: aliceGoal.id, amount: 0.01, amountMinorUnits: 1,
            currencyCode: "USD", xpEarned: 5, userID: alice
        )
        let justRecorded = SavingTransaction(
            goalId: aliceGoal.id, amount: 0.02, amountMinorUnits: 2,
            currencyCode: "USD", xpEarned: 7, userID: alice
        )
        let foreign = SavingTransaction(
            goalId: bobGoal.id, amount: 0.03, amountMinorUnits: 3,
            currencyCode: "USD", xpEarned: 8, userID: bob
        )
        let allGoals = [aliceGoal, bobGoal]
        let allTransactions = [offline, justRecorded, foreign]
        let ownedGoals = AccountScope.visibleGoals(allGoals, userID: alice)
            .filter { !$0.isGroupGoal }
        let ownedTransactions = AccountScope.visibleTransactions(
            allTransactions, goals: allGoals, userID: alice
        )
        XCTAssertEqual(Set(ownedTransactions.map(\.id)),
                       Set([offline.id, justRecorded.id]))
        let firstRetry = try PersonalSavingSyncBatch.make(
            goals: ownedGoals, transactions: ownedTransactions,
            authenticatedUserID: alice
        )
        XCTAssertEqual(Set(firstRetry.transactions.map(\.id)),
                       Set([offline.id, justRecorded.id]))
        XCTAssertEqual(firstRetry.transactions.map(\.xpEarned).reduce(0, +), 12)
        XCTAssertTrue(firstRetry.transactions.allSatisfy { $0.userID == alice })
        let secondRetry = try PersonalSavingSyncBatch.make(
            goals: ownedGoals, transactions: ownedTransactions,
            authenticatedUserID: alice
        )
        XCTAssertEqual(secondRetry.transactions, firstRetry.transactions)
        XCTAssertEqual(secondRetry.goals, firstRetry.goals)
    }

    /// A disconnected device must retain account-owned goals, savings and XP
    /// on disk before any cloud acknowledgement. Reopening and rebuilding the
    /// batch must preserve immutable UUIDs so upstream UPSERT retry is safe.
    /// HTTP rejection/ambiguous response is exercised separately by local
    /// Auth+PostgREST QA; this test is SwiftData persistence, not connectivity.
    @MainActor
    func testGlobalV1OfflinePendingSavingPersistsAndReplaysWithoutCrossAccountLeak() throws {
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-offline-retry-" + UUID().uuidString + ".store")
        let configuration = ModelConfiguration(schema: schema, url: url)
        let writerContainer = try ModelContainer(for: schema, configurations: [configuration])
        let writer = ModelContext(writerContainer)
        let alice = UUID(), bob = UUID()
        let goal = PersonalGoal(
            title: "Offline laptop", category: .gadget,
            targetAmount: 1500.50, currentAmount: 0.01,
            currencyCode: "USD", targetMinorUnits: 150_050,
            recordedMinorUnits: 1,
            targetDate: .now.addingTimeInterval(86_400 * 40),
            ownerUserID: alice
        )
        let saving = SavingTransaction(
            goalId: goal.id, amount: 0.01, amountMinorUnits: 1,
            currencyCode: "USD", xpEarned: 37, userID: alice
        )
        let profile = UserProfile(userID: alice, totalXP: 37)
        writer.insert(goal)
        writer.insert(saving)
        writer.insert(profile)
        try writer.save() // Simulates offline: no network request or server receipt.

        // A true disk reopen, not a second ModelContext over the same container.
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let reader = ModelContext(reopened)
        let allGoals = try reader.fetch(FetchDescriptor<PersonalGoal>())
        let allSavings = try reader.fetch(FetchDescriptor<SavingTransaction>())
        let aliceGoals = AccountScope.visibleGoals(allGoals, userID: alice)
            .filter { !$0.isGroupGoal }
        let aliceSavings = AccountScope.visibleTransactions(
            allSavings, goals: allGoals, userID: alice
        )
        XCTAssertEqual(aliceGoals.count, 1)
        XCTAssertEqual(aliceSavings.count, 1)
        XCTAssertEqual(aliceSavings[0].id, saving.id)
        XCTAssertEqual(aliceSavings[0].amountMinorUnits, 1)
        XCTAssertEqual(aliceGoals[0].recordedMinorUnits, 1)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<UserProfile>())
            .first(where: { $0.userID == alice })?.totalXP, 37)

        let firstTry = try PersonalSavingSyncBatch.make(
            goals: aliceGoals, transactions: aliceSavings,
            authenticatedUserID: alice
        )
        let retryAfterForeground = try PersonalSavingSyncBatch.make(
            goals: aliceGoals, transactions: aliceSavings,
            authenticatedUserID: alice
        )
        XCTAssertEqual(firstTry.goals, retryAfterForeground.goals)
        XCTAssertEqual(firstTry.transactions, retryAfterForeground.transactions)
        XCTAssertEqual(firstTry.goals[0].id, goal.id)
        XCTAssertEqual(firstTry.transactions[0].id, saving.id)
        XCTAssertEqual(firstTry.transactions[0].xpEarned, 37)
        XCTAssertEqual(firstTry.transactions[0].userID, alice)
        XCTAssertEqual(firstTry.goals[0].currencyCode, "USD")

        XCTAssertTrue(AccountScope.visibleGoals(allGoals, userID: bob).isEmpty)
        XCTAssertTrue(AccountScope.visibleTransactions(
            allSavings, goals: allGoals, userID: bob
        ).isEmpty)
        XCTAssertThrowsError(try PersonalSavingSyncBatch.make(
            goals: aliceGoals, transactions: aliceSavings,
            authenticatedUserID: bob
        ))
    }

    func testGlobalV1ScheduledContributionExplanationUsesGoalCurrency() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = try XCTUnwrap(PersonalSavingSchedule(
            targetAmount: 150_050,
            startDate: start,
            targetDate: start.addingTimeInterval(60 * 60 * 24 * 45),
            rhythm: .weekly,
            preferredDay: 2,
            calendar: Calendar(identifier: .gregorian)
        ))
        let usdAmount = PipoGoalCurrency.formatted(Int64(schedule.amount), code: "USD")
        let usdCopy = scheduleDetails(schedule, currencyCode: "USD")
        XCTAssertTrue(usdCopy.contains(usdAmount))
        XCTAssertFalse(usdCopy.contains("Rp"))

        let exactOverride = 12_550
        XCTAssertTrue(scheduleDetails(schedule, override: exactOverride, currencyCode: "USD")
            .contains(PipoGoalCurrency.formatted(Int64(exactOverride), code: "USD")))
        XCTAssertTrue(scheduleDetails(schedule, currencyCode: "JPY")
            .contains(PipoGoalCurrency.formatted(Int64(schedule.amount), code: "JPY")))
        XCTAssertTrue(scheduleDetails(schedule)
            .contains(PersonalPlanFormatting.rupiah(schedule.amount)))
    }

    @MainActor
    func testGlobalV1InterruptedOnboardingIsScopedAndDiscardedOnDeletion() {
        let owner = UUID()
        let another = UUID()
        OnboardingProfileStore.saveDraft(.init(
            stepNumber: OnboardingStep.motivation.rawValue,
            nickname: "Pipo friend",
            motivation: .excitingGoal
        ), for: owner)
        let draft = OnboardingProfileStore.loadDraft(for: owner)
        XCTAssertEqual(draft?.nickname, "Pipo friend")
        XCTAssertEqual(draft?.stepNumber, OnboardingStep.motivation.rawValue)
        XCTAssertNil(OnboardingProfileStore.loadDraft(for: another),
                     "Onboarding must never leak between accounts")
        OnboardingProfileStore.delete(for: owner)
        XCTAssertNil(OnboardingProfileStore.loadDraft(for: owner))
    }

    /// Uses a unique disk-backed synthetic SwiftData store (never the user's
    /// production container) to exercise the same relaunch persistence path.
    @MainActor
    func testGlobalV1GoalCurrencyAndExactHistorySurviveDiskReopen() throws {
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-currency-v1-" + UUID().uuidString + ".store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let first = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(first)
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Laptop in USD", category: .gadget,
            targetAmount: 1500.50, currentAmount: 100.25,
            currencyCode: "USD", targetMinorUnits: 150_050,
            recordedMinorUnits: 10_025,
            targetDate: .now.addingTimeInterval(86_400 * 45),
            ownerUserID: owner
        )
        let saving = SavingTransaction(
            goalId: goal.id, amount: 100.25, amountMinorUnits: 10_025,
            currencyCode: "USD", userID: owner
        )
        let profile = UserProfile(
            userID: owner, totalXP: 900, currentLevel: 2,
            unlockedBadgeIds: ["first-save"]
        )
        context.insert(goal)
        context.insert(saving)
        context.insert(profile)
        try context.save()

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let reader = ModelContext(reopened)
        let restored = try XCTUnwrap(reader.fetch(FetchDescriptor<PersonalGoal>())
            .first(where: { $0.id == goal.id }))
        XCTAssertEqual(restored.effectiveCurrencyCode, "USD")
        XCTAssertEqual(restored.exactTargetMinor, 150_050)
        XCTAssertEqual(restored.exactRecordedMinor, 10_025)
        let history = try XCTUnwrap(reader.fetch(FetchDescriptor<SavingTransaction>())
            .first(where: { $0.id == saving.id }))
        XCTAssertEqual(history.currencyCode, "USD")
        XCTAssertEqual(history.amountMinorUnits, 10_025)
        let savedProfile = try XCTUnwrap(reader.fetch(FetchDescriptor<UserProfile>())
            .first(where: { $0.userID == owner }))
        XCTAssertEqual(savedProfile.totalXP, 900)
        XCTAssertEqual(savedProfile.unlockedBadgeIds, ["first-save"])
    }

    func testApprovedBudgetBUsesRecordedBreakdownNotSampleAmounts() {
        let goalID = UUID()
        let rows = [
            PipoBudgetLine(id: goalID, title: "Travel & stay", amount: 4_500_000),
            PipoBudgetLine(id: UUID(), title: "Experiences", amount: 1_500_000),
            PipoBudgetLine(id: UUID(), title: "Documents", amount: 600_000)
        ]
        let target = 6_600_000.0

        XCTAssertEqual(rows.map { PipoBudgetPresentation.percent(of: $0.amount, target: target) },
                       [68, 23, 9])
        let total = PipoBudgetPresentation.validTotal(for: rows)
        XCTAssertEqual(total, target)
        XCTAssertTrue(PipoBudgetPresentation.matchesTarget(total: total ?? -1, target: target))
        XCTAssertEqual(rows.first?.id, goalID, "Rows should keep real persisted identity")
    }

    func testApprovedBudgetBNeverHidesMismatchOrInvalidAmount() {
        let rows = [
            PipoBudgetLine(id: UUID(), title: "Travel", amount: 250),
            PipoBudgetLine(id: UUID(), title: "Hotel", amount: 300)
        ]
        let total = PipoBudgetPresentation.validTotal(for: rows)
        XCTAssertEqual(total, 550)
        XCTAssertFalse(PipoBudgetPresentation.matchesTarget(total: total ?? -1, target: 600))
        XCTAssertNil(PipoBudgetPresentation.percent(of: 250, target: 0))
        XCTAssertNil(PipoBudgetPresentation.percent(of: -.infinity, target: 600))
        XCTAssertNil(PipoBudgetPresentation.validTotal(for: [
            PipoBudgetLine(id: UUID(), title: "Bad import", amount: -.infinity)
        ]))
        XCTAssertNil(PipoBudgetPresentation.validTotal(for: [
            PipoBudgetLine(id: UUID(), title: "Negative", amount: -1)
        ]))
    }

    func testAllCardsMoneyOutDraftRejectsInvalidAndOverAvailableAmounts() {
        XCTAssertEqual(PipoMoneyOutPreview.amount(from: "500000", available: 1_500_000), 500_000)
        XCTAssertNil(PipoMoneyOutPreview.amount(from: "0", available: 1_500_000))
        XCTAssertNil(PipoMoneyOutPreview.amount(from: "-1", available: 1_500_000))
        XCTAssertNil(PipoMoneyOutPreview.amount(from: "1500001", available: 1_500_000))
        XCTAssertNil(PipoMoneyOutPreview.amount(from: "100", available: -.infinity))
        XCTAssertNil(PipoMoneyOutPreview.amount(from: "invalid", available: 1_500_000))
    }

    func testAllCardsImpactIsPureAndDoesNotErasePriorSavingOrXP() {
        let goal = PersonalGoal(
            title: "Bali", category: .trip, targetAmount: 6_000_000,
            currentAmount: 1_500_000, targetDate: .now
        )
        let profile = UserProfile(totalXP: 600)
        let previousAmount = goal.currentAmount
        let previousXP = profile.totalXP
        XCTAssertEqual(PipoMoneyOutPreview.impact(before: goal.currentAmount, used: 500_000),
                       1_000_000)
        XCTAssertNil(PipoMoneyOutPreview.impact(before: goal.currentAmount, used: 1_500_001))
        XCTAssertNil(PipoMoneyOutPreview.impact(before: goal.currentAmount, used: -1))
        XCTAssertNil(PipoMoneyOutPreview.impact(before: .infinity, used: 500_000))
        XCTAssertEqual(goal.currentAmount, previousAmount, "Preview must never mutate a real goal")
        XCTAssertEqual(profile.totalXP, previousXP, "Preview must never erase earned XP")
    }

    func testApprovedCompletionAndFocusAreDerivedFromRealProgress() {
        let active = PersonalGoal(
            title: "Weekend", category: .trip, targetAmount: 1_000,
            currentAmount: 999, targetDate: .now
        )
        XCTAssertFalse(active.lifecycleState == .completed)
        XCTAssertEqual(active.progress, 0.999)
        active.currentAmount = 1_000
        XCTAssertTrue(active.lifecycleState == .completed)
        XCTAssertEqual(active.progress, 1)
    }

    func testProgressAndRemainingAmountAreBoundedByTarget() {
        let goal = PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 100,
            currentAmount: 125,
            targetDate: .now
        )

        XCTAssertEqual(goal.progress, 1)
        XCTAssertEqual(goal.remainingAmount, 0)
    }

    func testProgressIsZeroWhenTargetIsNotPositive() {
        let goal = PersonalGoal(
            title: "Emergency fund",
            category: .house,
            targetAmount: 0,
            currentAmount: 50,
            targetDate: .now
        )

        XCTAssertEqual(goal.progress, 0)
        XCTAssertEqual(goal.remainingAmount, 0)
    }

    func testMonthlyScheduleClampsToTheLastDayOfShortMonths() throws {
        let schedule = try XCTUnwrap(PersonalSavingSchedule(
            targetAmount: 100, startDate: date(2027, 2, 1), targetDate: date(2027, 4, 30),
            rhythm: .monthly, preferredDay: 31, calendar: calendar
        ))

        XCTAssertEqual(schedule.firstDate, date(2027, 2, 28))
        XCTAssertEqual(schedule.lastDate, date(2027, 4, 30))
        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule.amount, 34)
    }

    func testBiweeklyScheduleUsesTheChosenWeekdayAndTargetCutoff() throws {
        let schedule = try XCTUnwrap(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 2, 5),
            rhythm: .biWeekly, preferredDay: 2, calendar: calendar
        ))

        XCTAssertEqual(schedule.firstDate, date(2027, 1, 11))
        XCTAssertEqual(schedule.lastDate, date(2027, 1, 25))
        XCTAssertEqual(schedule.count, 2)
        XCTAssertEqual(schedule.amount, 450)
    }

    func testShortTimelineAndFlexibleRhythmHaveNoSchedule() {
        XCTAssertNil(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 1, 10),
            rhythm: .weekly, preferredDay: 2, calendar: calendar
        ))
        XCTAssertNil(PersonalSavingSchedule(
            targetAmount: 900, startDate: date(2027, 1, 5), targetDate: date(2027, 2, 5),
            rhythm: .flexible, preferredDay: nil, calendar: calendar
        ))
    }

    func testRupiahInputsAcceptIndonesianGroupSeparators() {
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("7.500.000"), 7_500_000)
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("Rp 7.500.000"), 7_500_000)
        XCTAssertEqual(PersonalPlanFormatting.parseRupiah("7500000"), 7_500_000)
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("7.50"))
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("0"))
        XCTAssertNil(PersonalPlanFormatting.parseRupiah("-100"))
    }


    func testLifecycleDefaultsAndPausedArchivedTransitions() {
        let goal = PersonalGoal(
            title: "Holiday", category: .trip,
            targetAmount: 1_000, currentAmount: 200,
            targetDate: .now
        )
        XCTAssertEqual(goal.lifecycleState, .active)
        XCTAssertTrue(goal.canRecordSaving)
        XCTAssertTrue(goal.transition(to: .paused))
        XCTAssertEqual(goal.lifecycleState, .paused)
        XCTAssertFalse(goal.canRecordSaving)
        XCTAssertFalse(goal.transition(to: .completed), "Only recorded progress completes a goal")
        XCTAssertTrue(goal.transition(to: .archived))
        XCTAssertEqual(goal.currentAmount, 200, "Archiving never loses recorded savings")
        XCTAssertTrue(goal.transition(to: .active))
        XCTAssertEqual(goal.lifecycleState, .active)
        XCTAssertNil(goal.lifecycleRaw)
        XCTAssertTrue(goal.canRecordSaving)
        goal.lifecycleRaw = "unknown-legacy-value"
        XCTAssertEqual(goal.lifecycleState, .active)
    }

    func testCompletingTargetBlocksMoreSavesAndCannotBeReopened() {
        let goal = PersonalGoal(
            title: "Camera", category: .gadget,
            targetAmount: 400, currentAmount: 200, targetDate: .now
        )
        XCTAssertTrue(goal.transition(to: .paused))
        goal.currentAmount = 440
        XCTAssertEqual(goal.progress, 1)
        XCTAssertEqual(goal.lifecycleState, .completed)
        XCTAssertFalse(goal.canRecordSaving)
        XCTAssertFalse(goal.transition(to: .active))
        XCTAssertFalse(goal.transition(to: .archived))
    }

    func testGamificationNeverAwardsXPForPausedOrCompletedGoal() {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Concert", category: .trip,
            targetAmount: 200, currentAmount: 50,
            targetDate: .now, ownerUserID: owner
        )
        let profile = UserProfile(userID: owner, totalXP: 600)
        let originalXP = profile.totalXP

        XCTAssertTrue(goal.transition(to: .paused))
        XCTAssertThrowsError(
            try GamificationManager().recordSaving(amount: 25, goal: goal, profile: profile)
        ) { error in
            guard case GamificationError.goalNotActive = error else {
                XCTFail("Expected a goal-not-active error, got \(error)")
                return
            }
        }
        XCTAssertEqual(goal.currentAmount, 50)
        XCTAssertEqual(profile.totalXP, originalXP)

        goal.currentAmount = 200
        XCTAssertThrowsError(
            try GamificationManager().recordSaving(amount: 25, goal: goal, profile: profile)
        )
        XCTAssertEqual(profile.totalXP, originalXP)
    }

    @MainActor
    func testLifecycleFocusPersistenceRemainsAccountScopedAfterReopen() throws {
        let accountA = UUID(), accountB = UUID()
        let container = try ModelContainer(
            for: Schema([PersonalGoal.self, SubItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let writer = ModelContext(container)
        let focusA = PersonalGoal(title: "A focus", category: .trip,
                                  targetAmount: 1_000, targetDate: .now,
                                  ownerUserID: accountA)
        let otherA = PersonalGoal(title: "A paused", category: .gift,
                                  targetAmount: 800, targetDate: .now,
                                  ownerUserID: accountA)
        let focusB = PersonalGoal(title: "B focus", category: .house,
                                  targetAmount: 5_000, targetDate: .now,
                                  ownerUserID: accountB)
        let unowned = PersonalGoal(title: "Legacy", category: .trip,
                                   targetAmount: 700, targetDate: .now)
        focusA.isFocusPreferred = true
        focusB.isFocusPreferred = true
        XCTAssertTrue(otherA.transition(to: .paused))
        for goal in [focusA, otherA, focusB, unowned] { writer.insert(goal) }
        try writer.save()

        let reader = ModelContext(container)
        let all = try reader.fetch(FetchDescriptor<PersonalGoal>())
        let ownedA = AccountScope.visibleGoals(all, userID: accountA)
        let ownedB = AccountScope.visibleGoals(all, userID: accountB)
        XCTAssertEqual(ownedA.filter { $0.isFocusPreferred == true }.map(\.id), [focusA.id])
        XCTAssertEqual(ownedB.filter { $0.isFocusPreferred == true }.map(\.id), [focusB.id])
        XCTAssertEqual(ownedA.first(where: { $0.id == otherA.id })?.lifecycleState, .paused)
        XCTAssertTrue(AccountScope.visibleGoals(all, userID: nil).isEmpty)
        XCTAssertEqual(all.count, 4, "Legacy rows remain quarantined")
    }


    @MainActor
    func testIssue21WidgetDeepLinkRequiresLiveOwnedActivePersonalGoal() {
        let alice = UUID(), bob = UUID()
        let personal = PersonalGoal(
            title: "Retirement", category: .house, targetAmount: 1_000,
            currentAmount: 100, targetDate: .now, ownerUserID: alice
        )
        XCTAssertTrue(AccountScope.canOpenWidgetSavingRequest(personal, userID: alice))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(personal, userID: bob))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(personal, userID: nil))
        XCTAssertTrue(personal.transition(to: .paused))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(personal, userID: alice))
        XCTAssertTrue(personal.transition(to: .archived))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(personal, userID: alice))
        XCTAssertTrue(personal.transition(to: .active))
        XCTAssertTrue(AccountScope.canOpenWidgetSavingRequest(personal, userID: alice))
        personal.currentAmount = 1_100
        XCTAssertEqual(personal.lifecycleState, .completed)
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(personal, userID: alice))

        let group = PersonalGoal(
            title: "Trip with friends", category: .trip,
            targetAmount: 500, targetDate: .now,
            isGroupGoal: true, ownerUserID: alice
        )
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(group, userID: alice))
        let orphan = PersonalGoal(
            title: "Unverified legacy", category: .gift,
            targetAmount: 500, targetDate: .now
        )
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(orphan, userID: alice))
    }

    @MainActor
    func testIssue21DiskBackedStatusFocusAndJournalSurviveReopenWithoutCrossAccountLeak() throws {
        let ownerA = UUID(), ownerB = UUID()
        let schema = Schema([
            PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-issue21-lifecycle-" + UUID().uuidString + ".store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let config = ModelConfiguration(schema: schema, url: url)
        let first = try ModelContainer(for: schema, configurations: [config])
        let writer = ModelContext(first)

        let aActive = PersonalGoal(
            title: "A focus", category: .trip, targetAmount: 1_000,
            currentAmount: 200, targetDate: .now, ownerUserID: ownerA,
            isFocusPreferred: true
        )
        let aPaused = PersonalGoal(
            title: "A paused", category: .gift, targetAmount: 800,
            currentAmount: 75, targetDate: .now, ownerUserID: ownerA
        )
        let aArchived = PersonalGoal(
            title: "A archived", category: .house, targetAmount: 900,
            currentAmount: 50, targetDate: .now, ownerUserID: ownerA
        )
        let aCompleted = PersonalGoal(
            title: "A completed", category: .gadget, targetAmount: 100,
            currentAmount: 120, targetDate: .now, ownerUserID: ownerA
        )
        let bActive = PersonalGoal(
            title: "B focus", category: .trip, targetAmount: 4_000,
            targetDate: .now, ownerUserID: ownerB, isFocusPreferred: true
        )
        let unowned = PersonalGoal(
            title: "Legacy without verified ownership", category: .other,
            targetAmount: 2_000, targetDate: .now
        )
        XCTAssertTrue(aPaused.transition(to: .paused))
        XCTAssertTrue(aArchived.transition(to: .archived))
        let aJournal = SavingTransaction(
            goalId: aActive.id, amount: 200, xpEarned: 300, userID: ownerA
        )
        let profileA = UserProfile(
            userID: ownerA, totalXP: 300,
            unlockedBadgeIds: [PipoBadge.firstSave.rawValue]
        )
        for goal in [aActive, aPaused, aArchived, aCompleted, bActive, unowned] {
            writer.insert(goal)
        }
        writer.insert(aJournal)
        writer.insert(profileA)
        try writer.save()

        // A separate container and context must read the disk-backed database.
        // Reusing a second ModelContext on the same container would not prove
        // relaunch persistence.
        let second = try ModelContainer(for: schema, configurations: [config])
        let reader = ModelContext(second)
        let all = try reader.fetch(FetchDescriptor<PersonalGoal>())
        let allEntries = try reader.fetch(FetchDescriptor<SavingTransaction>())
        let allProfiles = try reader.fetch(FetchDescriptor<UserProfile>())
        let alice = AccountScope.visibleGoals(all, userID: ownerA)
        let bob = AccountScope.visibleGoals(all, userID: ownerB)
        XCTAssertEqual(Set(alice.map(\.id)),
                       Set([aActive.id, aPaused.id, aArchived.id, aCompleted.id]))
        XCTAssertEqual(bob.map(\.id), [bActive.id])
        XCTAssertTrue(AccountScope.visibleGoals(all, userID: nil).isEmpty)
        XCTAssertFalse(alice.contains { $0.id == unowned.id })

        let restoredFocus = try XCTUnwrap(alice.first { $0.id == aActive.id })
        let restoredPause = try XCTUnwrap(alice.first { $0.id == aPaused.id })
        let restoredArchive = try XCTUnwrap(alice.first { $0.id == aArchived.id })
        let restoredCompleted = try XCTUnwrap(alice.first { $0.id == aCompleted.id })
        XCTAssertEqual(restoredFocus.isFocusPreferred, true)
        XCTAssertEqual(restoredPause.lifecycleState, .paused)
        XCTAssertEqual(restoredArchive.lifecycleState, .archived)
        XCTAssertEqual(restoredCompleted.lifecycleState, .completed)
        XCTAssertEqual(restoredCompleted.currentAmount, 120)
        XCTAssertEqual(restoredCompleted.progress, 1)
        XCTAssertFalse(restoredCompleted.transition(to: .active))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(restoredPause, userID: ownerA))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(restoredArchive, userID: ownerA))
        XCTAssertFalse(AccountScope.canOpenWidgetSavingRequest(restoredCompleted, userID: ownerA))

        let aliceEntries = AccountScope.visibleTransactions(
            allEntries, goals: all, userID: ownerA
        )
        XCTAssertEqual(aliceEntries.map(\.id), [aJournal.id])
        XCTAssertTrue(AccountScope.visibleTransactions(
            allEntries, goals: all, userID: ownerB
        ).isEmpty)
        XCTAssertEqual(UserProfile.existing(for: ownerA, in: allProfiles)?.totalXP, 300)
        XCTAssertEqual(UserProfile.existing(for: ownerA, in: allProfiles)?.unlockedBadgeIds,
                       [PipoBadge.firstSave.rawValue])
        XCTAssertNil(UserProfile.existing(for: ownerB, in: allProfiles))

        XCTAssertTrue(restoredPause.transition(to: .active))
        XCTAssertTrue(restoredArchive.transition(to: .active))
        try reader.save()
        let third = try ModelContainer(for: schema, configurations: [config])
        let reread = ModelContext(third)
        let again = try reread.fetch(FetchDescriptor<PersonalGoal>())
        let ownerGoals = AccountScope.visibleGoals(again, userID: ownerA)
        XCTAssertEqual(ownerGoals.first(where: { $0.id == aPaused.id })?.lifecycleState,
                       .active)
        XCTAssertEqual(ownerGoals.first(where: { $0.id == aArchived.id })?.lifecycleState,
                       .active)
        XCTAssertEqual(ownerGoals.first(where: { $0.id == aActive.id })?.isFocusPreferred, true)
        XCTAssertEqual(ownerGoals.first(where: { $0.id == aCompleted.id })?.currentAmount, 120)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

extension PersonalGoalTests {

    @MainActor
    func testAccountSwitchShowsOnlyOwnedGoalsAndTransactions() throws {
        let accountA = UUID()
        let accountB = UUID()
        let container = try ModelContainer(
            for: Schema([PersonalGoal.self, SubItem.self, SavingTransaction.self, UserProfile.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let goalA = PersonalGoal(title: "Private A", category: .trip,
                                 targetAmount: 1_000, targetDate: .now,
                                 ownerUserID: accountA)
        let goalB = PersonalGoal(title: "Private B", category: .gadget,
                                 targetAmount: 2_000, targetDate: .now,
                                 ownerUserID: accountB)
        let oldGoal = PersonalGoal(title: "Legacy unowned", category: .trip,
                                   targetAmount: 3_000, targetDate: .now)
        context.insert(goalA)
        context.insert(goalB)
        context.insert(oldGoal)
        context.insert(SavingTransaction(goalId: goalA.id, amount: 100, userID: accountA))
        context.insert(SavingTransaction(goalId: goalB.id, amount: 200, userID: accountB))
        // A transaction may claim B in its metadata, but still points at A's goal.
        context.insert(SavingTransaction(goalId: goalA.id, amount: 999, userID: accountB))
        context.insert(SavingTransaction(goalId: oldGoal.id, amount: 444, userID: nil))
        try context.save()

        let reopened = ModelContext(container)
        let goals = try reopened.fetch(FetchDescriptor<PersonalGoal>())
        let entries = try reopened.fetch(FetchDescriptor<SavingTransaction>())
        XCTAssertEqual(Set(AccountScope.visibleGoals(goals, userID: accountA).map(\.id)), [goalA.id])
        XCTAssertEqual(Set(AccountScope.visibleGoals(goals, userID: accountB).map(\.id)), [goalB.id])
        XCTAssertTrue(AccountScope.visibleGoals(goals, userID: nil).isEmpty)
        XCTAssertEqual(AccountScope.visibleTransactions(entries, goals: goals, userID: accountA).map(\.amount), [100])
        XCTAssertEqual(AccountScope.visibleTransactions(entries, goals: goals, userID: accountB).map(\.amount), [200])
        XCTAssertTrue(AccountScope.visibleTransactions(entries, goals: goals, userID: nil).isEmpty)

        // Legacy records remain on disk/in the store and are never silently claimed.
        XCTAssertEqual(goals.count, 3)
        XCTAssertNil(try XCTUnwrap(goals.first(where: { $0.id == oldGoal.id })).ownerUserID)
        XCTAssertEqual(entries.count, 4)
    }

    @MainActor
    func testUnownedLegacyProfileIsNotAdoptedOnNextSignIn() throws {
        let accountA = UUID()
        let accountB = UUID()
        let legacy = UserProfile(totalXP: 5_000, unlockedBadgeIds: ["private-badge"])
        let owned = UserProfile(userID: accountA, totalXP: 80)
        let profiles = [legacy, owned]
        XCTAssertEqual(UserProfile.existing(for: accountA, in: profiles)?.id, owned.id)
        XCTAssertNil(UserProfile.existing(for: accountB, in: profiles))
        XCTAssertNil(UserProfile.existing(for: nil, in: profiles))
        XCTAssertNil(legacy.userID)
    }

    func testWidgetSnapshotsAreHiddenAcrossAccountSwitchAndLogout() throws {
        let suite = "pipo.widget.account-scope.qa.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = UUID()
        let accountB = UUID()
        let goalID = UUID()
        let snapshot = WidgetSnapshot(
            streakDays: 2, totalXP: 600, currentLevel: 1,
            goalID: goalID, goalTitle: "Private savings",
            goalProgress: 0.4, nextDepositDate: nil, ownerUserID: accountA
        )

        WidgetSharedData.activate(userID: accountA, in: defaults)
        try WidgetSharedData.save(snapshot, in: defaults)
        XCTAssertEqual(WidgetSharedData.load(from: defaults).goalID, goalID)

        WidgetSharedData.activate(userID: accountB, in: defaults)
        XCTAssertNil(WidgetSharedData.load(from: defaults).goalID)
        XCTAssertThrowsError(try WidgetSharedData.save(snapshot, in: defaults))

        // An upgrade can encounter a legacy snapshot without an owner tag.
        defaults.set(["goalID": goalID.uuidString, "goalTitle": "Old savings"],
                     forKey: "pipo.widget.snapshot")
        XCTAssertNil(WidgetSharedData.load(from: defaults).goalTitle)

        WidgetSharedData.activate(userID: nil, in: defaults)
        XCTAssertEqual(WidgetSharedData.load(from: defaults).totalXP, 0)
    }

    @MainActor
    func testGroupReviewPersistsLocalMetadataAndSingleTargetWithoutMockRows() throws {
        var draft = GroupPlanDraft()
        draft.title = "Supplies"
        draft.category = .other
        draft.customCategory = "Studio"
        draft.groupName = "Art club"
        draft.targetText = "1.250.000"
        draft.mode = .flexible
        draft.checkIn = .weekly
        try draft.prepareMember("Ari")
        let owner = UUID()
        let review = try XCTUnwrap(draft.review(creatorID: owner))
        let schema = Schema([PersonalGoal.self, SubItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let writer = ModelContext(container)
        try review.insertGoal(in: writer, ownerUserID: owner)
        try writer.save()

        let reader = ModelContext(container)
        let goal = try XCTUnwrap(reader.fetch(FetchDescriptor<PersonalGoal>()).first)
        XCTAssertEqual(goal.title, "Supplies")
        XCTAssertEqual(goal.categoryTitle, "Studio")
        XCTAssertEqual(goal.ownerUserID, owner)
        XCTAssertEqual(goal.rhythm, .flexible)
        XCTAssertEqual(goal.targetAmount, 1_250_000)
        XCTAssertTrue(goal.subItems.isEmpty)
        XCTAssertTrue(goal.isGroupGoal)
        let details = try JSONDecoder().decode(GroupPlanDetails.self, from: XCTUnwrap(goal.groupDetails))
        XCTAssertEqual(details.groupName, "Art club")
        XCTAssertEqual(details.checkIn, .weekly)
        XCTAssertEqual(details.creatorID, owner)
        XCTAssertEqual(details.preparedMembers, ["Ari"])
        XCTAssertEqual(review.members.map(\.status), [.accepted])
    }
}

extension PersonalGoalTests {
    @MainActor
    func testIssue48PhotoNormalizesWithoutChangingSavingRecords() throws {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "A real photo goal", category: .trip,
            targetAmount: 1_000_000, currentAmount: 250_000,
            targetDate: Date(timeIntervalSinceNow: 90 * 86_400),
            ownerUserID: owner
        )
        // Fix the pixel density explicitly: the default renderer inherits
        // the 3x simulator screen scale, producing a 960x1500 PNG instead.
        let fixtureFormat = UIGraphicsImageRendererFormat()
        fixtureFormat.scale = 1
        let input = UIGraphicsImageRenderer(
            size: CGSize(width: 320, height: 500),
            format: fixtureFormat
        ).pngData { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 500))
        }
        let clean = try PipoGoalPhotoProcessing.prepare(input)
        XCTAssertTrue(clean.starts(with: [0xFF, 0xD8]))
        let outputImage = try XCTUnwrap(UIImage(data: clean))
        XCTAssertEqual(outputImage.size.width, 320)
        XCTAssertEqual(outputImage.size.height, 500)
        goal.goalPhoto = clean
        XCTAssertEqual(goal.currentAmount, 250_000)
        XCTAssertEqual(goal.targetAmount, 1_000_000)
        XCTAssertEqual(goal.progress, 0.25)
        goal.goalPhoto = nil
        XCTAssertNil(goal.goalPhoto)
        XCTAssertEqual(goal.currentAmount, 250_000)
    }


    @MainActor
    func testIssue48HighDensityImageIsCappedAt1600Pixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let input = UIGraphicsImageRenderer(
            size: CGSize(width: 500, height: 800), format: format
        ).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 500, height: 800))
        }
        let resized = try PipoGoalPhotoProcessing.prepare(input)
        let output = try XCTUnwrap(UIImage(data: resized))
        XCTAssertEqual(output.size.width, 1_000)
        XCTAssertEqual(output.size.height, 1_600)
        XCTAssertLessThanOrEqual(resized.count, 1_500_000)
        XCTAssertTrue(resized.starts(with: [0xFF, 0xD8]))
    }

    @MainActor
    func testIssue48RejectsUnreadableAndOversizedPhotoData() {
        XCTAssertThrowsError(try PipoGoalPhotoProcessing.prepare(Data()))
        XCTAssertThrowsError(try PipoGoalPhotoProcessing.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(
            try PipoGoalPhotoProcessing.prepare(
                Data(repeating: 0xFE, count: 12 * 1024 * 1024 + 1)
            )
        )
    }
}

extension PersonalGoalTests {
    func testIssue42TargetRevisionKeepsRecordedSavingsIntact() throws {
        let before = 1_500_000
        let preview = try PlanFinancialPreview.revisedTarget(
            netRecorded: before, target: 6_600_000,
            futurePeriods: 20, breakdown: [3_600_000, 3_000_000]
        )
        XCTAssertEqual(preview.netRecorded, before)
        XCTAssertEqual(preview.remaining, 5_100_000)
        XCTAssertEqual(preview.proposedPerPeriod, 255_000)
    }

    func testIssue42MoneyOutIndependentKeepDateAndKeepAmount() throws {
        let preview = try MoneyOutFinancialPreview.calculate(
            netRecorded: 1_500_000, target: 6_000_000,
            moneyTakenOut: 500_000, futurePeriods: 20,
            currentPerPeriod: 225_000
        )
        XCTAssertEqual(preview.revisedNetRecorded, 1_000_000)
        XCTAssertEqual(preview.remaining, 5_000_000)
        XCTAssertEqual(preview.keepDatePerPeriod, 250_000)
        XCTAssertEqual(preview.keepAmountPeriods, 23)
        XCTAssertEqual(preview.keepAmountFinalContribution, 50_000)
    }

    func testIssue42InsufficientSavingsAndInvalidAmountsFailClosed() {
        XCTAssertThrowsError(try MoneyOutFinancialPreview.calculate(
            netRecorded: 1_500_000, target: 6_000_000,
            moneyTakenOut: 2_000_000, futurePeriods: 20,
            currentPerPeriod: 225_000
        )) { error in
            XCTAssertEqual(error as? PlanFinancialPreviewError, .insufficientSavings)
        }
        XCTAssertThrowsError(try MoneyOutFinancialPreview.calculate(
            netRecorded: 1_500_000, target: 6_000_000,
            moneyTakenOut: 0, futurePeriods: 20,
            currentPerPeriod: 225_000
        ))
        XCTAssertThrowsError(try PlanFinancialPreview.revisedTarget(
            netRecorded: 1_500_000, target: 6_600_000,
            futurePeriods: 20, breakdown: [3_000_000]
        ))
    }
}

 
extension PersonalGoalTests {
    func testIssue42CorrectionRetainsPastXPAndReconstructsNet() throws {
        let oldXP = 900
        let result = try MoneyOutCorrectionPreview.calculate(
            currentNetRecorded: 1_000_000, originalMoneyOut: 500_000,
            correctedMoneyOut: 300_000
        )
        XCTAssertEqual(result.correctedNetRecorded, 1_200_000)
        XCTAssertEqual(result.adjustmentDelta, 200_000)
        XCTAssertEqual(oldXP, 900, "A correction cannot award or erase XP")
    }

    func testIssue42CorrectionRejectsOverdrawAndZero() {
        XCTAssertThrowsError(try MoneyOutCorrectionPreview.calculate(
            currentNetRecorded: 100_000, originalMoneyOut: 50_000,
            correctedMoneyOut: 200_000
        ))
        XCTAssertThrowsError(try MoneyOutCorrectionPreview.calculate(
            currentNetRecorded: 100_000, originalMoneyOut: 50_000,
            correctedMoneyOut: 0
        ))
    }
}


extension PersonalGoalTests {
    func testIssue42LedgerReconstructsMoneyOutAndCorrectionWithoutXPLoss() throws {
        let owner = UUID(), goal = UUID(), original = UUID()
        let saving = SavingTransaction(goalId: goal, amount: 1_500_000,
                                       xpEarned: 300, userID: owner)
        let events = [
            SavingAdjustmentEvent(id: original, goalID: goal, userID: owner,
                                  kind: .moneyOut, amount: 500_000,
                                  correctsEventID: nil, date: .now),
            SavingAdjustmentEvent(id: UUID(), goalID: goal, userID: owner,
                                  kind: .correction, amount: 200_000,
                                  correctsEventID: original, date: .now)
        ]
        let snapshot = try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving], adjustments: events
        )
        XCTAssertEqual(snapshot.netRecorded, 1_200_000)
        XCTAssertEqual(snapshot.earnedXP, 300)
    }

    func testIssue42LedgerRejectsForeignAccountAndDuplicateRetry() throws {
        let owner = UUID(), goal = UUID(), eventID = UUID()
        let saving = SavingTransaction(goalId: goal, amount: 900_000,
                                       xpEarned: 300, userID: owner)
        let one = SavingAdjustmentEvent(id: eventID, goalID: goal, userID: owner,
                                        kind: .moneyOut, amount: 100_000,
                                        correctsEventID: nil, date: .now)
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: UUID(), savings: [saving], adjustments: [one]
        ))
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving], adjustments: [one, one]
        )) { error in
            XCTAssertEqual(error as? SavingLedgerError, .duplicateEvent)
        }
    }

    func testIssue42LedgerCannotOverdrawOrAttachCorrectionToMissingEvent() {
        let owner = UUID(), goal = UUID()
        let saving = SavingTransaction(goalId: goal, amount: 100_000,
                                       xpEarned: 300, userID: owner)
        let tooMuch = SavingAdjustmentEvent(id: UUID(), goalID: goal, userID: owner,
                                            kind: .moneyOut, amount: 150_000,
                                            correctsEventID: nil, date: .now)
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving], adjustments: [tooMuch]
        ))
        let orphanCorrection = SavingAdjustmentEvent(
            id: UUID(), goalID: goal, userID: owner, kind: .correction,
            amount: 25_000, correctsEventID: UUID(), date: .now
        )
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving],
            adjustments: [orphanCorrection]
        ))
    }
}


extension PersonalGoalTests {
    func testIssue42CloudRecoveryValidatesSignedOwnerAndPreservesXP() throws {
        let owner = UUID(), goal = UUID(), originalID = UUID(), correctionID = UUID()
        let json = JSONDecoder()
        json.dateDecodingStrategy = .iso8601
        let savingsData = """
        [{"id":"\(UUID().uuidString)","goal_id":"\(goal.uuidString)",
          "user_id":"\(owner.uuidString)","amount":1500000,
          "xp_earned":300,"date":"2026-11-19T12:00:00Z"}]
        """.data(using: .utf8)!
        let correctionData = """
        [
          {"id":"\(originalID.uuidString)","goal_id":"\(goal.uuidString)",
           "user_id":"\(owner.uuidString)","kind":"money_out","amount":500000,
           "corrects_event_id":null,"created_at":"2026-11-19T13:00:00Z"},
          {"id":"\(correctionID.uuidString)","goal_id":"\(goal.uuidString)",
           "user_id":"\(owner.uuidString)","kind":"correction","amount":200000,
           "corrects_event_id":"\(originalID.uuidString)","created_at":"2026-11-19T14:00:00Z"}
        ]
        """.data(using: .utf8)!
        let contributions = try json.decode([SavingLedgerCloudContribution].self, from: savingsData)
        let adjustments = try json.decode([SavingLedgerCloudAdjustment].self, from: correctionData)
        let snapshot = try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: owner,
            contributions: contributions, adjustments: adjustments
        )
        XCTAssertEqual(snapshot.netRecorded, 1_200_000)
        XCTAssertEqual(snapshot.earnedXP, 300)
        XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: UUID(),
            contributions: contributions, adjustments: adjustments
        ))
    }

    func testIssue42CloudRecoveryRejectsUnknownAdjustmentTypeAndFractionalAmount() throws {
        let owner = UUID(), goal = UUID()
        let json = JSONDecoder()
        json.dateDecodingStrategy = .iso8601
        let base = """
        [{"id":"\(UUID().uuidString)","goal_id":"\(goal.uuidString)",
          "user_id":"\(owner.uuidString)","kind":"money_out",
          "amount":999,"corrects_event_id":null,
          "created_at":"2026-11-19T13:00:00Z"}]
        """
        for altered in [base.replacingOccurrences(of: "money_out", with: "transfer"),
                        base.replacingOccurrences(of: "\"amount\":999", with: "\"amount\":999.5")] {
            let entries = try json.decode(
                [SavingLedgerCloudAdjustment].self, from: altered.data(using: .utf8)!
            )
            XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
                goalID: goal, ownerID: owner, contributions: [], adjustments: entries
            ))
        }
    }

    func testIssue42CloudRecoveryRejectsOverLimitPayloads() {
        let owner = UUID(), goal = UUID()
        let sample = SavingLedgerCloudAdjustment(
            id: UUID(), goalID: goal, userID: owner, kind: "money_out",
            amount: 1, correctsEventID: nil, createdAt: "2026-11-19T13:00:00.123456+00:00"
        )
        XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: owner,
            contributions: [], adjustments: Array(repeating: sample, count: 10_001)
        )) { error in
            XCTAssertEqual(error as? SavingCloudRecoveryError, .tooManyEntries)
        }
    }
}

extension PersonalGoalTests {
    func testIssue42CloudRecoveryAcceptsPostgresFractionalTimestamp() throws {
        let user = UUID(), goal = UUID()
        let data = """
        [{"id":"\(UUID().uuidString)","goal_id":"\(goal.uuidString)",
          "user_id":"\(user.uuidString)","amount":100000,"xp_earned":300,
          "date":"2026-11-19T12:00:00.123456+00:00"}]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([SavingLedgerCloudContribution].self, from: data)
        let snapshot = try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: user, contributions: rows, adjustments: []
        )
        XCTAssertEqual(snapshot.netRecorded, 100_000)
        XCTAssertEqual(snapshot.earnedXP, 300)
    }
}

extension PersonalGoalTests {
    func testIssue42MoneyOutRPCRequestUsesStableIdempotencyIDAndExpectedKeys() throws {
        let requestID = UUID(), goalID = UUID()
        let request = try SavingMoneyOutRPCRequest(
            requestID: requestID, goalID: goalID, amount: 500_000,
            note: "  Used for school  ", preference: "keep_date"
        )
        let payload = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as! [String: Any]
        XCTAssertEqual(payload["p_id"] as? String, requestID.uuidString)
        XCTAssertEqual(payload["p_goal_id"] as? String, goalID.uuidString)
        XCTAssertEqual(payload["p_amount"] as? Int, 500_000)
        XCTAssertEqual(payload["p_note"] as? String, "Used for school")
        XCTAssertEqual(payload["p_preference"] as? String, "keep_date")
        XCTAssertEqual(request.requestID, requestID, "Use the same UUID after retry")
    }

    func testIssue42MoneyOutRPCRejectsOverdrawShapedInputsBeforeNetwork() {
        let goalID = UUID()
        for amount in [0, -100, 10_000_000_000_000_000] {
            XCTAssertThrowsError(try SavingMoneyOutRPCRequest(
                requestID: UUID(), goalID: goalID, amount: amount,
                note: nil, preference: "keep_amount"
            ))
        }
        XCTAssertThrowsError(try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: goalID, amount: 100,
            note: String(repeating: "x", count: 241),
            preference: "keep_amount"
        ))
        XCTAssertThrowsError(try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: goalID, amount: 100,
            note: nil, preference: "other"
        ))
    }

    func testIssue42MoneyOutRPCRejectsForgedOrConflictingServerReceipt() throws {
        let owner = UUID()
        let request = try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: 500_000,
            note: "Coffee", preference: "keep_date"
        )
        let accepted = SavingMoneyOutRPCReceipt(
            id: request.requestID, goalID: request.goalID, userID: owner,
            kind: "money_out", amount: 500_000,
            preference: "keep_date", note: "Coffee"
        )
        XCTAssertNoThrow(try accepted.verify(request: request, ownerID: owner))
        XCTAssertThrowsError(try accepted.verify(
            request: request, ownerID: UUID()
        ))
        let altered = SavingMoneyOutRPCReceipt(
            id: request.requestID, goalID: request.goalID, userID: owner,
            kind: "money_out", amount: 600_000,
            preference: "keep_date", note: "Coffee"
        )
        XCTAssertThrowsError(try altered.verify(request: request, ownerID: owner))
    }
}

extension PersonalGoalTests {
    func testIssue42AtomicCloudSnapshotEnvelopeFailsClosedOnWrongIdentity() throws {
        let goal = UUID(), owner = UUID(), other = UUID()
        let payload = """
        {"goal_id":"\(goal.uuidString)","user_id":"\(owner.uuidString)",
         "contributions":[],"adjustments":[]}
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(
            SavingLedgerCloudSnapshotEnvelope.self, from: payload
        )
        XCTAssertEqual(envelope.goalID, goal)
        XCTAssertEqual(envelope.userID, owner)
        XCTAssertNotEqual(envelope.userID, other)
        XCTAssertEqual(
            try SavingCloudLedgerReconciler.reconstruct(
                goalID: goal, ownerID: owner,
                contributions: envelope.contributions,
                adjustments: envelope.adjustments
            ).netRecorded, 0
        )
    }
}

extension PersonalGoalTests {
    @MainActor
    func testIssue42OfflineJournalSurvivesReopenAndScopesByAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-moneyout-qa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), another = UUID()
        let request = try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: 80_000,
            note: "Train", preference: "keep_date"
        )
        let writer = MoneyOutIntentJournal(directory: directory)
        let staged = try writer.stage(request, ownerID: owner)
        XCTAssertEqual(staged.state, .staged)
        XCTAssertEqual(try writer.all(for: another).count, 0)

        // Reconstruct from disk as after a process restart or loss of network.
        let reopened = MoneyOutIntentJournal(directory: directory)
        XCTAssertEqual(try reopened.all(for: owner).count, 1)
        XCTAssertEqual(try reopened.all(for: owner).first?.request.requestID,
                       request.requestID)
        XCTAssertEqual(try reopened.stage(request, ownerID: owner).createdAt,
                       staged.createdAt)
        XCTAssertEqual(try reopened.all(for: owner).count, 1)

        let conflict = try SavingMoneyOutRPCRequest(
            requestID: request.requestID, goalID: request.goalID,
            amount: 90_000, note: "Train", preference: "keep_date"
        )
        XCTAssertThrowsError(try reopened.stage(conflict, ownerID: owner)) {
            XCTAssertEqual($0 as? MoneyOutJournalError, .idempotencyConflict)
        }
        XCTAssertEqual(try reopened.all(for: another).count, 0)
    }

    @MainActor
    func testIssue42OfflineJournalRequiresVerifiedReceiptAndReadback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-moneyout-qa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let request = try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: 50_000,
            note: "Taxi", preference: "keep_amount"
        )
        let journal = MoneyOutIntentJournal(directory: directory)
        try journal.stage(request, ownerID: owner)
        let receipt = SavingMoneyOutRPCReceipt(
            id: request.requestID, goalID: request.goalID,
            userID: owner, kind: "money_out", amount: 50_000,
            preference: "keep_amount", note: "Taxi"
        )
        let invalidReceipt = SavingMoneyOutRPCReceipt(
            id: request.requestID, goalID: request.goalID,
            userID: UUID(), kind: "money_out", amount: 50_000,
            preference: "keep_amount", note: "Taxi"
        )
        XCTAssertThrowsError(try journal.acknowledge(
            requestID: request.requestID,
            receipt: invalidReceipt, ownerID: owner
        ))
        XCTAssertEqual(try journal.all(for: owner).first?.state, .staged)
        try journal.acknowledge(
            requestID: request.requestID, receipt: receipt, ownerID: owner
        )
        XCTAssertEqual(try MoneyOutIntentJournal(directory: directory)
            .all(for: owner).first?.state, .acknowledged)

        let emptyCloud = SavingLedgerCloudSnapshotEnvelope(
            goalID: request.goalID, userID: owner,
            contributions: [], adjustments: []
        )
        XCTAssertThrowsError(try journal.finishVerifiedReadback(
            requestID: request.requestID, cloud: emptyCloud, ownerID: owner
        ))
        XCTAssertEqual(try journal.all(for: owner).count, 1)
        let snapshotCloud = SavingLedgerCloudSnapshotEnvelope(
            goalID: request.goalID, userID: owner,
            contributions: [SavingLedgerCloudContribution(
                id: UUID(), goalID: request.goalID, userID: owner,
                amount: 100_000, xpEarned: 300,
                date: "2026-11-20T00:00:00Z"
            )],
            adjustments: [SavingLedgerCloudAdjustment(
                id: request.requestID, goalID: request.goalID,
                userID: owner, kind: "money_out", amount: 50_000,
                correctsEventID: nil, createdAt: "2026-11-20T00:10:00.000Z"
            )]
        )
        let snapshot = try journal.finishVerifiedReadback(
            requestID: request.requestID, cloud: snapshotCloud,
            ownerID: owner
        )
        XCTAssertEqual(snapshot.netRecorded, 50_000)
        XCTAssertEqual(snapshot.earnedXP, 300)
        XCTAssertTrue(try journal.all(for: owner).isEmpty)
    }

    @MainActor
    func testIssue42OfflineJournalRejectsCorruptionInsteadOfLosingIntent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-moneyout-qa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try Data("bad JSON".utf8).write(
            to: directory.appendingPathComponent(
                owner.uuidString.lowercased() + ".json"
            )
        )
        let journal = MoneyOutIntentJournal(directory: directory)
        XCTAssertThrowsError(try journal.all(for: owner)) {
            XCTAssertEqual($0 as? MoneyOutJournalError, .invalidJournal)
        }
        let request = try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: 1000,
            note: nil, preference: "keep_date"
        )
        XCTAssertThrowsError(try journal.stage(request, ownerID: owner))
    }
}

// #42: a cloud ledger must never credit money that was not originally logged.
extension PersonalGoalTests {
    func testIssue42LedgerRejectsPhantomSavingsCorrection() {
        let owner = UUID(), goal = UUID(), withdrawalID = UUID()
        let saving = SavingTransaction(
            goalId: goal, amount: 1_500_000, xpEarned: 300, userID: owner
        )
        let withdrawal = SavingAdjustmentEvent(
            id: withdrawalID, goalID: goal, userID: owner,
            kind: .moneyOut, amount: 500_000,
            correctsEventID: nil, date: .now
        )
        let impossibleCorrection = SavingAdjustmentEvent(
            id: UUID(), goalID: goal, userID: owner,
            kind: .correction, amount: 600_000,
            correctsEventID: withdrawalID, date: .now
        )
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving],
            adjustments: [withdrawal, impossibleCorrection]
        )) { error in
            XCTAssertEqual(error as? SavingLedgerError, .malformedEvent)
        }
    }

    func testIssue42LedgerRejectsOverReversedRepeatedCorrections() throws {
        let owner = UUID(), goal = UUID(), withdrawalID = UUID()
        let saving = SavingTransaction(
            goalId: goal, amount: 1_500_000, xpEarned: 300, userID: owner
        )
        let withdrawal = SavingAdjustmentEvent(
            id: withdrawalID, goalID: goal, userID: owner,
            kind: .moneyOut, amount: 500_000,
            correctsEventID: nil, date: .now
        )
        let first = SavingAdjustmentEvent(
            id: UUID(), goalID: goal, userID: owner,
            kind: .correction, amount: 200_000,
            correctsEventID: withdrawalID, date: .now
        )
        let tooMuch = SavingAdjustmentEvent(
            id: UUID(), goalID: goal, userID: owner,
            kind: .correction, amount: 350_000,
            correctsEventID: withdrawalID, date: .now
        )
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving],
            adjustments: [first, withdrawal, tooMuch]
        )) { error in
            XCTAssertEqual(error as? SavingLedgerError, .malformedEvent)
        }

        // Increasing an already-corrected money-out is legitimate as long as
        // the recorded balance remains non-negative and XP stays unchanged.
        let validAdjustment = SavingAdjustmentEvent(
            id: UUID(), goalID: goal, userID: owner,
            kind: .correction, amount: -100_000,
            correctsEventID: withdrawalID, date: .now
        )
        let valid = try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner, savings: [saving],
            adjustments: [first, withdrawal, validAdjustment]
        )
        XCTAssertEqual(valid.netRecorded, 1_100_000)
        XCTAssertEqual(valid.earnedXP, 300)
    }

    func testIssue42CloudRecoveryRejectsPhantomSavingsCorrection() {
        let owner = UUID(), goal = UUID(), withdrawalID = UUID()
        let original = SavingLedgerCloudAdjustment(
            id: withdrawalID, goalID: goal, userID: owner,
            kind: "money_out", amount: 500_000,
            correctsEventID: nil, createdAt: "2026-11-19T13:00:00Z"
        )
        let forged = SavingLedgerCloudAdjustment(
            id: UUID(), goalID: goal, userID: owner,
            kind: "correction", amount: 600_000,
            correctsEventID: withdrawalID,
            createdAt: "2026-11-19T13:01:00Z"
        )
        let saving = SavingLedgerCloudContribution(
            id: UUID(), goalID: goal, userID: owner,
            amount: 1_500_000, xpEarned: 300,
            date: "2026-11-19T12:00:00Z"
        )
        XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: owner,
            contributions: [saving], adjustments: [original, forged]
        )) { error in
            XCTAssertEqual(error as? SavingLedgerError, .malformedEvent)
        }
    }
}

extension PersonalGoalTests {
    @MainActor
    func testIssue42JournalRejectsNoncanonicalSavedRequest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipo-moneyout-qa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let request = try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: 5_000,
            note: "Coffee", preference: "keep_date"
        )
        let journal = MoneyOutIntentJournal(directory: directory)
        try journal.stage(request, ownerID: owner)

        // A malformed on-disk request must not silently acquire a different
        // retry payload under the same idempotency key.
        let fileURL = directory.appendingPathComponent(
            owner.uuidString.lowercased() + ".json"
        )
        let original = try String(contentsOf: fileURL, encoding: .utf8)
        let altered = original.replacingOccurrences(
            of: "\"p_note\":\"Coffee\"",
            with: "\"p_note\":\" Coffee \""
        )
        XCTAssertNotEqual(original, altered)
        try Data(altered.utf8).write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try MoneyOutIntentJournal(
            directory: directory
        ).all(for: owner)) { error in
            XCTAssertEqual(error as? MoneyOutJournalError, .invalidJournal)
        }
    }
}

extension PersonalGoalTests {
    func testIssue42RejectsUnrepresentableWholeIDRAmounts() throws {
        let largestExact = SavingsAmountSafety.maxExactWholeIDR
        let firstLossy = largestExact + 1

        XCTAssertNoThrow(try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: largestExact,
            note: nil, preference: "keep_date"
        ))
        XCTAssertThrowsError(try SavingMoneyOutRPCRequest(
            requestID: UUID(), goalID: UUID(), amount: firstLossy,
            note: nil, preference: "keep_date"
        )) { error in
            XCTAssertEqual(error as? SavingMoneyOutRequestError, .invalidAmount)
        }

        XCTAssertThrowsError(try PlanFinancialPreview.revisedTarget(
            netRecorded: 0, target: firstLossy, futurePeriods: 2
        )) { error in
            XCTAssertEqual(error as? PlanFinancialPreviewError, .invalidTarget)
        }
        XCTAssertThrowsError(try MoneyOutFinancialPreview.calculate(
            netRecorded: 1_000, target: firstLossy,
            moneyTakenOut: 500, futurePeriods: 4,
            currentPerPeriod: 250
        )) { error in
            XCTAssertEqual(error as? PlanFinancialPreviewError, .invalidTarget)
        }
    }

    func testIssue42CloudRecoveryRejectsLossyAmounts() {
        let owner = UUID(), goal = UUID()
        let invalidAmount = Double(SavingsAmountSafety.maxExactWholeIDR + 1)
        let contribution = SavingLedgerCloudContribution(
            id: UUID(), goalID: goal, userID: owner,
            amount: invalidAmount, xpEarned: 300,
            date: "2026-11-20T00:00:00Z"
        )
        XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: owner,
            contributions: [contribution], adjustments: []
        )) { error in
            XCTAssertEqual(error as? SavingCloudRecoveryError, .invalidServerEntry)
        }

        let invalidAdjustment = SavingLedgerCloudAdjustment(
            id: UUID(), goalID: goal, userID: owner,
            kind: "money_out", amount: invalidAmount,
            correctsEventID: nil, createdAt: "2026-11-20T00:01:00Z"
        )
        XCTAssertThrowsError(try SavingCloudLedgerReconciler.reconstruct(
            goalID: goal, ownerID: owner,
            contributions: [], adjustments: [invalidAdjustment]
        )) { error in
            XCTAssertEqual(error as? SavingCloudRecoveryError, .invalidServerEntry)
        }
    }

    func testIssue42LedgerRejectsAggregateBeyondExactIDRLimit() {
        let owner = UUID(), goal = UUID()
        let contribution1 = SavingTransaction(
            goalId: goal, amount: 5_000_000_000_000_000,
            xpEarned: 300, userID: owner
        )
        let contribution2 = SavingTransaction(
            goalId: goal, amount: 5_000_000_000_000_000,
            xpEarned: 300, userID: owner
        )
        XCTAssertThrowsError(try SavingLedgerSnapshot.reconstruct(
            goalID: goal, ownerID: owner,
            savings: [contribution1, contribution2], adjustments: []
        )) { error in
            XCTAssertEqual(error as? SavingLedgerError, .invalidMoney)
        }
    }
}

extension PersonalGoalTests {
    func testManagePlanV2CurrencyMinorUnitsAndStrictFormatting() {
        let idr = Locale(identifier: "id_ID")
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PipoPlanV2Money.fractionDigits(for: "IDR"), 0)
        XCTAssertEqual(PipoPlanV2Money.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(PipoPlanV2Money.fractionDigits(for: "USD"), 2)
        XCTAssertEqual(PipoPlanV2Money.editable(
            Decimal(6_000_000), currency: "IDR", locale: idr
        ), "6.000.000")
        XCTAssertEqual(PipoPlanV2Money.parse(
            PipoPlanV2Money.editable(Decimal(string: "1234.56")!, currency: "USD"),
            currency: "USD"
        ), Decimal(string: "1234.56"))
        XCTAssertEqual(PipoPlanV2Money.parse(
            PipoPlanV2Money.editable(Decimal(6_000_000), currency: "IDR", locale: us),
            currency: "IDR", locale: us
        ), Decimal(6_000_000))
        XCTAssertEqual(PipoPlanV2Money.parse("6,000,000", currency: "IDR", locale: us),
                       Decimal(6_000_000))
        XCTAssertEqual(PipoPlanV2Money.parse("6.600.000", currency: "IDR", locale: idr),
                       Decimal(6_600_000))
        XCTAssertNil(PipoPlanV2Money.parse("6.600.000,50", currency: "IDR", locale: idr))
        XCTAssertEqual(PipoPlanV2Money.parse("1,234.56", currency: "USD", locale: us),
                       Decimal(string: "1234.56"))
        XCTAssertNil(PipoPlanV2Money.parse("1,234.567", currency: "USD", locale: us))
        XCTAssertNil(PipoPlanV2Money.parse("1,23,4.56", currency: "USD", locale: us))
        XCTAssertNil(PipoPlanV2Money.parse("1,234.50", currency: "JPY", locale: us))
        XCTAssertNil(PipoPlanV2Money.parse("1e3", currency: "USD", locale: us))
        XCTAssertNil(PipoPlanV2Money.parse("-100", currency: "USD", locale: us))
        XCTAssertNil(PipoPlanV2Money.parse("0", currency: "IDR", locale: idr))
        XCTAssertNil(PipoPlanV2Money.parse("99999999999999999", currency: "IDR", locale: idr))
        XCTAssertEqual(PipoPlanV2Money.suggested(Decimal(101), periods: 4, currency: "IDR"),
                       Decimal(26))
        XCTAssertEqual(PipoPlanV2Money.suggested(Decimal(1), periods: 8, currency: "USD"),
                       Decimal(string: "0.13"))
    }

    func testManagePlanV2FutureSavingPeriodsUseCalendarNotMockNumbers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)))
        let finish = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 2, day: 20)))
        let extended = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 3, day: 20)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let weekly = PipoPlanV2Cadence.remainingCount(
            originalStart: start, finish: finish, rhythm: .weekly,
            preferredDay: 3, now: now, calendar: calendar
        )
        XCTAssertEqual(weekly, 13, "Includes Nov 24; design's 12 was an illustrative December start.")
        let more = PipoPlanV2Cadence.remainingCount(
            originalStart: start, finish: extended, rhythm: .weekly,
            preferredDay: 3, now: now, calendar: calendar
        )
        XCTAssertEqual(more, 17)
        XCTAssertNil(PipoPlanV2Cadence.remainingCount(
            originalStart: start, finish: finish, rhythm: .flexible,
            preferredDay: nil, now: now, calendar: calendar
        ))
        XCTAssertEqual(PipoPlanV2Cadence.remainingCount(
            originalStart: start, finish: now, rhythm: .weekly,
            preferredDay: 3, now: now, calendar: calendar
        ), 0)
    }

    @MainActor
    func testManagePlanV2BudgetMismatchAndFlexiblePreserveOriginalHistory() throws {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Bali holiday", category: .trip, targetAmount: 6_000_000,
            currentAmount: 3_600_000,
            subItems: [
                SubItem(title: "Flights", amount: 2_000_000),
                SubItem(title: "Accommodation", amount: 2_500_000),
                SubItem(title: "Activities", amount: 1_000_000),
                SubItem(title: "Other", amount: 500_000)
            ],
            startDate: .now,
            targetDate: Calendar.current.date(byAdding: .month, value: 4, to: .now)!,
            rhythm: .weekly, preferredSavingDay: 3, ownerUserID: owner
        )
        let saving = SavingTransaction(goalId: goal.id, amount: 3_600_000, xpEarned: 300, userID: owner)
        let original = PipoPlanV2Original(goal: goal)
        var draft = PipoPlanV2Draft(original: original)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(original.recorded, Decimal(3_600_000))
        XCTAssertEqual(goal.progress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(draft.target, Decimal(6_000_000))
        // Grouping is determined by the display locale, not the goal currency.
        // CI uses en_US while Indonesian devices commonly use id_ID.
        draft.targetInput = PipoPlanV2Money.editable(Decimal(6_000_000), currency: "IDR")
        XCTAssertFalse(draft.isDirty, "Equivalent locale grouping is not a real edit")
        draft.targetInput = "6600000"
        XCTAssertTrue(draft.isDirty)
        XCTAssertNotNil(draft.validationError, "Existing item allocation must reconcile")
        let index = try XCTUnwrap(draft.budget.firstIndex(where: { $0.title == "Activities" }))
        draft.budget[index].input = "1600000"
        XCTAssertEqual(draft.allocationTotal, Decimal(6_600_000))
        XCTAssertNil(draft.validationError)

        draft.rhythm = .flexible
        draft.preferredDay = nil
        XCTAssertNil(draft.suggested(), "Flexible must never produce a required scheduled amount")
        XCTAssertNil(draft.validationError, "Flexible has no deadline or streak enforcement")
        XCTAssertEqual(goal.targetAmount, 6_000_000)
        XCTAssertEqual(goal.currentAmount, 3_600_000)
        XCTAssertEqual(saving.xpEarned, 300)
        XCTAssertEqual(saving.amount, 3_600_000)
        XCTAssertEqual(goal.rhythm, .weekly, "Draft cannot mutate persisted cadence")
        XCTAssertEqual(goal.subItems.first(where: { $0.title == "Activities" })?.amount, 1_000_000)
    }

    @MainActor
    func testManagePlanV2BlocksOverfundingAndRestoresSemanticNoChange() {
        let goal = PersonalGoal(
            title: "Bali holiday", category: .trip,
            targetAmount: 6_000_000, currentAmount: 3_600_000,
            targetDate: Calendar.current.date(byAdding: .month, value: 2, to: .now)!,
            rhythm: .weekly, preferredSavingDay: 3
        )
        let original = PipoPlanV2Original(goal: goal)
        var draft = PipoPlanV2Draft(original: original)
        draft.targetInput = "3500000"
        XCTAssertTrue(draft.validationError?.contains("below") == true)
        draft.targetInput = "6000000"
        XCTAssertFalse(draft.isDirty)
        draft.rhythm = .flexible
        draft.preferredDay = nil
        XCTAssertTrue(draft.isDirty)
        draft.rhythm = .weekly
        draft.preferredDay = 3
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(goal.currentAmount, 3_600_000)
    }
}
