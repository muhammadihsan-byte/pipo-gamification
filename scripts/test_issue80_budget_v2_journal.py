"""Compile/run dormant Budget CAS V2 durable journal with production Swift contracts.

Uses isolated ephemeral Foundation storage. No Supabase, DB writes or Mac runner.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from scripts.test_issue80_client_contract import APP_SOURCE, FIXTURE
from scripts.test_issue80_budget_cas_v2_client import BEGIN, END

HARNESS = r'''
import Foundation

func require(_ value: Bool, _ explanation: String) {
    if !value { fatalError(explanation) }
}
func rejects(_ type: SavingPlanBudgetV2JournalError,
             _ action: () throws -> Void) {
    do {
        try action()
        fatalError("Expected rejection: \(type)")
    } catch let error as SavingPlanBudgetV2JournalError {
        require(error == type, "Unexpected error \(error), wanted \(type)")
    } catch {
        fatalError("Unexpected exception: \(error)")
    }
}
func rejectsContract(_ action: () throws -> Void) {
    do {
        try action()
        fatalError("Expected V2 receipt contract rejection")
    } catch is SavingPlanBudgetV2ContractError {
    } catch {
        fatalError("Unexpected exception: \(error)")
    }
}
let owner = UUID(), otherOwner = UUID(), goalID = UUID(), requestID = UUID()
let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
let budget = try [
    SavingPlanBudgetV2Item(id: UUID(), title: "Transport", minorUnits: 60,
                           currencyCode: "USD", isCompleted: false),
    SavingPlanBudgetV2Item(id: UUID(), title: "Hotel", minorUnits: 40,
                           currencyCode: "USD", isCompleted: true)
]
func makeRequest(_ rid: UUID, _ gid: UUID, day: Int = 3)
    throws -> SavingPlanBudgetV2Request {
    try SavingPlanBudgetV2Request(
        requestID: rid, goalID: gid, expectedRevision: 0, ownerID: owner,
        currencyCode: "USD", targetMinorUnits: 100,
        targetDate: dueDate, rhythm: "weekly", preferredSavingDay: day,
        plannedContributionMinorUnits: 25, items: budget,
        cloudBudgetNeedsReview: true, userReviewedBudget: true)
}
let request = try makeRequest(requestID, goalID)
let budgetJSON = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(budget)
)
func receipt(_ edits: [String: Any] = [:]) throws
    -> SavingPlanBudgetV2WireResponse {
    var values: [String:Any] = [
        "status": "applied", "request_id": requestID.uuidString,
        "goal_id": goalID.uuidString, "accepted_revision": 1,
        "currency_code": "USD", "budget_snapshot_state": "synced",
        "target_amount": 1.0, "target_date": request.targetDate,
        "rhythm": "weekly", "preferred_saving_day": 3,
        "planned_contribution_override": 0.25, "items": budgetJSON
    ]
    for (key, value) in edits { values[key] = value }
    return try JSONDecoder().decode(SavingPlanBudgetV2WireResponse.self,
        from: JSONSerialization.data(withJSONObject: values))
}
func snapshot(_ edits: [String: Any] = [:]) throws
    -> SavingPlanBudgetV2CloudSnapshot {
    var values: [String:Any] = [
        "status": "snapshot", "goal_id": goalID.uuidString,
        "plan_revision": 1, "currency_code": "USD",
        "budget_snapshot_state": "synced", "target_amount": 1.0,
        "target_date": request.targetDate, "rhythm": "weekly",
        "preferred_saving_day": 3,
        "planned_contribution_override": 0.25, "items": budgetJSON
    ]
    for (key, value) in edits { values[key] = value }
    return try JSONDecoder().decode(SavingPlanBudgetV2CloudSnapshot.self,
        from: JSONSerialization.data(withJSONObject: values))
}
let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("pipo-budget-v2-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }
let journal = SavingPlanBudgetV2IntentJournal(directory: directory)
let first = try journal.stage(request, ownerID: owner)
require(first.state == .staged, "New journal entry is staged")
let replay = try journal.stage(request, ownerID: owner)
require(replay == first, "Identical replay must keep original UUID and payload")
rejects(.accountChanged) {
    _ = try journal.stage(request, ownerID: otherOwner)
}
rejects(.idempotencyConflict) {
    _ = try journal.stage(makeRequest(requestID, goalID, day: 4),
                          ownerID: owner)
}
rejects(.goalAlreadyPending) {
    _ = try journal.stage(makeRequest(UUID(), goalID), ownerID: owner)
}

let reopened = SavingPlanBudgetV2IntentJournal(directory: directory)
require(try reopened.pending(for: owner).first == first,
        "Reopen must preserve item order, IDs and completion flags")
require(try reopened.pending(for: otherOwner).isEmpty,
        "Owner-B journal cannot see owner A's stored requests")
let wrongAmount = try receipt(["target_amount":1.01])
rejectsContract {
    try reopened.recordVerifiedResponse(wrongAmount,
        requestID: requestID, ownerID: owner)
}
require(try reopened.pending(for: owner).first?.state == .staged,
        "Untrusted receipt must leave intent untouched")

try reopened.recordVerifiedResponse(try receipt(),
    requestID: requestID, ownerID: owner)
let acknowledged = try reopened.pending(for: owner).first!
require(acknowledged.state == .acknowledged,
        "RPC receipt is not final verification")
require(acknowledged.responseRevision == 1, "Must retain response revision")

rejects(.accountChanged) {
    try reopened.recordAuthenticatedCurrentReadback(try snapshot(),
        requestID: requestID, ownerID: owner, authenticatedOwnerID: otherOwner)
}
rejects(.unverifiedReadback) {
    try reopened.recordAuthenticatedCurrentReadback(
        try snapshot(["budget_snapshot_state":"needs_review"]),
        requestID: requestID, ownerID: owner, authenticatedOwnerID: owner)
}
rejects(.unverifiedReadback) {
    try reopened.recordAuthenticatedCurrentReadback(
        try snapshot(["plan_revision":2]),
        requestID: requestID, ownerID: owner, authenticatedOwnerID: owner)
}
let reversed = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(Array(budget.reversed())))
rejects(.unverifiedReadback) {
    try reopened.recordAuthenticatedCurrentReadback(
        try snapshot(["items":reversed]), requestID: requestID,
        ownerID: owner, authenticatedOwnerID: owner)
}
require(try reopened.pending(for: owner).first?.state == .acknowledged,
        "Bad server readback cannot finalize acknowledgement")
try reopened.recordAuthenticatedCurrentReadback(try snapshot(),
    requestID: requestID, ownerID: owner, authenticatedOwnerID: owner)
require(try reopened.pending(for: owner).first?.state == .verified,
        "Verified remote is NOT a local SwiftData merge")
let afterRestart = SavingPlanBudgetV2IntentJournal(directory: directory)
require(try afterRestart.pending(for: owner).first?.state == .verified,
        "Verified intent persists after relaunch instead of silently deleting")
rejects(.goalAlreadyPending) {
    _ = try afterRestart.stage(makeRequest(UUID(), goalID), ownerID: owner)
}

// A separate goal can have an independent in-flight mutation.
let secondGoal = UUID()
let secondID = UUID()
_ = try afterRestart.stage(makeRequest(secondID, secondGoal), ownerID: owner)
let conflict: SavingPlanBudgetV2WireResponse = try JSONDecoder().decode(
    SavingPlanBudgetV2WireResponse.self,
    from: Data(("{\"status\":\"conflict\",\"goal_id\":\"" +
        secondGoal.uuidString + "\",\"current_revision\":2}").utf8))
try afterRestart.recordVerifiedResponse(
    conflict, requestID: secondID, ownerID: owner)
rejects(.userDecisionRequired) {
    try afterRestart.discardConflictedAfterUserDecision(
        requestID: secondID, ownerID: owner, userConfirmedDiscard: false)
}
try afterRestart.discardConflictedAfterUserDecision(
    requestID: secondID, ownerID: owner, userConfirmedDiscard: true)
require(try afterRestart.pending(for: owner).count == 1,
        "Discarded intent hidden, verified first goal still retained")
require(try afterRestart.all(for: owner).count == 2,
        "Discard leaves durable UUID tombstone")
rejects(.idempotencyConflict) {
    _ = try afterRestart.stage(
        makeRequest(secondID, secondGoal, day: 4), ownerID: owner)
}

// Simulate tampered on-disk JSON: fail closed for ALL pending entries.
let path = directory.appendingPathComponent(owner.uuidString.lowercased() + ".json")
try Data("not JSON".utf8).write(to: path, options: [.atomic])
rejects(.invalidJournal) { _ = try afterRestart.all(for: owner) }
print("PASS: Budget V2 journal durable, idempotent, owner isolated, readback-checked and tamper resistant")
'''

class BudgetCASV2JournalChecks(unittest.TestCase):
    def test_journal_remains_nonproduction_unwired(self):
        content = APP_SOURCE.read_text()
        self.assertEqual(content.count("final class SavingPlanBudgetV2IntentJournal"), 1)
        self.assertIn("PipoPendingBudgetCASV2", content)
        self.assertIn(".completeFileProtectionUnlessOpen", content)
        self.assertIn("SavingPlanBudgetV2SnapshotVerifier", content)
        self.assertNotIn('client.rpc("pipo_apply_plan_budget_v2"', content)

    def test_compiles_and_runs_real_swift_persistence_and_recovery(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Swift compiler not installed; GitHub Ubuntu CI has swiftc")
        source = APP_SOURCE.read_text()
        self.assertEqual(source.count(BEGIN), 1)
        self.assertEqual(source.count(END), 1)
        only = source.split(BEGIN, 1)[1].split(END, 1)[0]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Contract.swift").write_text(FIXTURE + "\n" + only)
            (root / "main.swift").write_text(HARNESS)
            binary = root / "journal"
            compiled = subprocess.run(
                [swiftc, "-swift-version", "5", "-o", str(binary),
                 str(root / "Contract.swift"), str(root / "main.swift")],
                capture_output=True, text=True, timeout=90
            )
            self.assertEqual(compiled.returncode, 0,
                             compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True,
                                 text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS: Budget V2 journal durable", run.stdout)


if __name__ == "__main__":
    unittest.main()
