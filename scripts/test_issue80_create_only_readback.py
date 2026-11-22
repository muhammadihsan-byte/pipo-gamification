"""Issue #80: Compile the dormant goal INSERT-only/readback contract on Linux.

No PostgREST call, no Supabase secrets, no database migration. Only the
exact production Swift Foundation block is compiled with the same limited
currency fixture used for PR #82's existing CAS-contract test.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from scripts.test_issue80_client_contract import (
    APP_SOURCE, START, END, FIXTURE,
)

HARNESS = r'''
import Foundation

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

let goalID = UUID()
let ownerID = UUID()
let foreignOwner = UUID()
let epoch = Date(timeIntervalSince1970: 1_800_000_000)
let target = Date(timeIntervalSince1970: 1_810_000_000)
let request = try SavingGoalCreateOnlyRequest(
    goalID: goalID, ownerID: ownerID,
    title: "  Camera  ", category: "gadget", customCategory: nil,
    targetMinorUnits: 30, currencyCode: "USD",
    startDate: epoch, targetDate: target,
    rhythm: "weekly", preferredSavingDay: 2,
    plannedContributionMinorUnits: 10
)
require(request.title == "Camera", "Canonical trimmed title")
require(request.targetAmount == Decimal(string: "0.30")!, "Exact USD 30 cents")
let raw = try JSONEncoder().encode(request)
let initial = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
let expectedKeys: Set<String> = [
    "id", "title", "category", "custom_category", "target_amount",
    "currency_code", "start_date", "target_date", "rhythm",
    "preferred_saving_day", "planned_contribution_override"
]
require(Set(initial.keys) == expectedKeys, "INSERT-only columns")
require(initial["user_id"] == nil, "Never supply user_id; server owns it")
require(initial["plan_revision"] == nil, "Never supply server-owned revision")
require(initial["created_at"] == nil, "Never spoof created_at")
require(initial["updated_at"] == nil, "Never spoof updated_at")
require(initial["target_amount"] as? NSNumber == NSNumber(value: 0.3),
        "Wire amount must be numeric major units")
require(initial["planned_contribution_override"] as? NSNumber
        == NSNumber(value: 0.1), "Future contribution in major units")
require(initial["custom_category"] is NSNull, "Keep explicit null budget name")

func serverRow(_ edits: [String: Any] = [:]) throws
    -> SavingGoalAuthoritativeCloudRow {
    var row = initial
    row["user_id"] = ownerID.uuidString
    row["plan_revision"] = 0
    for (key, value) in edits { row[key] = value }
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    return try JSONDecoder().decode(SavingGoalAuthoritativeCloudRow.self, from: data)
}
func mustReject(_ expectation: SavingGoalCreateContractError,
                _ action: () throws -> Void) {
    do {
        try action()
        fatalError("Expected fail-closed error \(expectation)")
    } catch let error as SavingGoalCreateContractError {
        require(error == expectation, "Wrong rejection \(error)")
    } catch {
        fatalError("Unexpected error \(error)")
    }
}
let canonical = try serverRow()
try SavingGoalCreateReadbackVerifier.verify(
    canonical, for: request, authenticatedOwnerID: ownerID
)
try SavingGoalCreateReadbackVerifier.verify(
    try serverRow([
        "start_date": request.startDate.replacingOccurrences(
            of: "Z", with: ".000+00:00"),
        "target_date": request.targetDate.replacingOccurrences(
            of: "Z", with: "+00:00")
    ]), for: request, authenticatedOwnerID: ownerID
)
mustReject(.accountChanged) {
    try SavingGoalCreateReadbackVerifier.verify(
        canonical, for: request, authenticatedOwnerID: foreignOwner
    )
}
mustReject(.missingOrInvisible) {
    try SavingGoalCreateReadbackVerifier.verify(
        nil, for: request, authenticatedOwnerID: ownerID
    )
}
mustReject(.mismatchedRemoteGoal) {
    try SavingGoalCreateReadbackVerifier.verify(
        serverRow(["user_id": foreignOwner.uuidString]),
        for: request, authenticatedOwnerID: ownerID
    )
}
mustReject(.mismatchedRemoteGoal) {
    try SavingGoalCreateReadbackVerifier.verify(
        serverRow(["id": UUID().uuidString]),
        for: request, authenticatedOwnerID: ownerID
    )
}
mustReject(.remotelyRevised) {
    try SavingGoalCreateReadbackVerifier.verify(
        serverRow(["plan_revision": 1]),
        for: request, authenticatedOwnerID: ownerID
    )
}
for altered in [
    ["title": "Another camera"],
    ["target_amount": 0.31],
    ["currency_code": "IDR"],
    ["rhythm": "daily"],
    ["preferred_saving_day": 3],
    ["planned_contribution_override": 0.11],
    ["start_date": "2027-01-01T00:00:00Z"],
    ["target_date": "2027-09-01T00:00:00Z"],
    ["category": "trip"]
] {
    mustReject(.mismatchedRemoteGoal) {
        try SavingGoalCreateReadbackVerifier.verify(
            serverRow(altered), for: request, authenticatedOwnerID: ownerID
        )
    }
}
func createAttempt(
    _ minor: Int64 = 30, _ currency: String = "USD",
    _ name: String = "Camera", _ rhythm: String = "weekly",
    _ day: Int? = 2, _ overrideMinor: Int64? = nil,
    _ from: Date = epoch, _ to: Date = target
) throws -> SavingGoalCreateOnlyRequest {
    try SavingGoalCreateOnlyRequest(
        goalID: goalID, ownerID: ownerID, title: name,
        category: "gadget", customCategory: nil,
        targetMinorUnits: minor, currencyCode: currency,
        startDate: from, targetDate: to,
        rhythm: rhythm, preferredSavingDay: day,
        plannedContributionMinorUnits: overrideMinor
    )
}
mustReject(.invalidAmount) { _ = try createAttempt(0) }
mustReject(.invalidAmount) { _ = try createAttempt(Int64.max) }
mustReject(.invalidAmount) { _ = try createAttempt(30, "KWD") }
mustReject(.invalidGoal) { _ = try createAttempt(30, "USD", " ") }
mustReject(.invalidSchedule) { _ = try createAttempt(30, "USD", "Camera", "weekly", 8) }
mustReject(.invalidSchedule) { _ = try createAttempt(30, "USD", "Camera", "flexible", nil, 10) }
mustReject(.invalidSchedule) { _ = try createAttempt(30, "USD", "Camera", "weekly", 2, nil, target, epoch) }
let flexible = try createAttempt(6000000, "IDR", "Vacation", "flexible", nil)
let flexWire = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(flexible)) as! [String: Any]
require(flexWire["preferred_saving_day"] is NSNull, "Flexible day must be null")
require(flexWire["planned_contribution_override"] is NSNull,
        "Flexible override must be null")
// The production journal is @MainActor. Keep all operations isolated while
// testing real atomic files and process reconstruction, no HTTP calls.
try MainActor.assumeIsolated {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "pipo-first-goal-qa-" + UUID().uuidString, isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = SavingGoalCreateIntentJournal(directory: dir)
    let initial = try first.stage(request, ownerID: ownerID)
    require(initial.state == .staged && initial.observedRevision == nil,
            "New goal must remain staged")
    require(try first.stage(request, ownerID: ownerID) == initial,
            "Exact create replay reuses original UUID and data")
    require(try first.all(for: foreignOwner).isEmpty,
            "An absent owner has a separate empty queue")
    let afterRelaunch = SavingGoalCreateIntentJournal(directory: dir)
    require(try afterRelaunch.all(for: ownerID).count == 1,
            "Atomic queue must survive reconstruction")
    require(try afterRelaunch.all(for: ownerID)[0].goalID == goalID,
            "Stable original goal UUID must survive relaunch")

    func expectJournal(
        _ expected: SavingGoalCreateJournalError,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            fatalError("Expected journal failure \(expected)")
        } catch let failure as SavingGoalCreateJournalError {
            require(failure == expected, "Unexpected journal error \(failure)")
        } catch {
            fatalError("Unexpected thrown error \(error)")
        }
    }

    let sameIDButChangedPayload = try SavingGoalCreateOnlyRequest(
        goalID: goalID, ownerID: ownerID, title: "Different target",
        category: "gadget", customCategory: nil,
        targetMinorUnits: 31, currencyCode: "USD",
        startDate: epoch, targetDate: target, rhythm: "weekly",
        preferredSavingDay: 2, plannedContributionMinorUnits: 10
    )
    expectJournal(.idempotencyConflict) {
        _ = try afterRelaunch.stage(sameIDButChangedPayload, ownerID: ownerID)
    }
    expectJournal(.accountChanged) {
        _ = try afterRelaunch.stage(request, ownerID: foreignOwner)
    }
    // A successful INSERT or a 409/timeout is NOT enough to advance this
    // state; there is intentionally no "mark HTTP success" method.
    do {
        _ = try afterRelaunch.recordReadback(
            nil, goalID: goalID, ownerID: ownerID,
            authenticatedOwnerID: ownerID
        )
        fatalError("Missing readback was considered success")
    } catch SavingGoalCreateContractError.missingOrInvisible {}
    require(try afterRelaunch.all(for: ownerID)[0].state == .staged,
            "Missing readback preserves staged state")
    expectJournal(.accountChanged) {
        _ = try afterRelaunch.recordReadback(
            canonical, goalID: goalID, ownerID: ownerID,
            authenticatedOwnerID: foreignOwner
        )
    }
    expectJournal(.untrustedReadback) {
        _ = try afterRelaunch.recordReadback(
            serverRow(["user_id": foreignOwner.uuidString]),
            goalID: goalID, ownerID: ownerID,
            authenticatedOwnerID: ownerID
        )
    }
    require(try afterRelaunch.all(for: ownerID)[0].state == .staged,
            "Foreign response must not mutate staged request")

    let verified = try afterRelaunch.recordReadback(
        canonical, goalID: goalID, ownerID: ownerID,
        authenticatedOwnerID: ownerID
    )
    require(verified == .verified, "Matching original row verified")
    require(try afterRelaunch.recordReadback(
        canonical, goalID: goalID, ownerID: ownerID,
        authenticatedOwnerID: ownerID
    ) == .verified, "Same verified result is idempotent")
    require(try afterRelaunch.all(for: ownerID)[0].observedRevision == 0,
            "Verified create preserves revision zero")
    expectJournal(.invalidTransition) {
        _ = try afterRelaunch.recordReadback(
            serverRow(["plan_revision": 2]),
            goalID: goalID, ownerID: ownerID,
            authenticatedOwnerID: ownerID
        )
    }
    expectJournal(.invalidTransition) {
        try afterRelaunch.discardConflictedAfterUserDecision(
            goalID: goalID, ownerID: ownerID,
            userConfirmedDiscard: true
        )
    }
    require(try afterRelaunch.all(for: ownerID).count == 1,
            "Verified entry is NOT erased until future local merge gate")

    let conflictGoal = UUID()
    let conflictRequest = try SavingGoalCreateOnlyRequest(
        goalID: conflictGoal, ownerID: ownerID, title: "Trip",
        category: "trip", customCategory: nil,
        targetMinorUnits: 100, currencyCode: "USD",
        startDate: epoch, targetDate: target, rhythm: "flexible",
        preferredSavingDay: nil, plannedContributionMinorUnits: nil
    )
    try afterRelaunch.stage(conflictRequest, ownerID: ownerID)
    func conflictRow(_ changes: [String: Any] = [:]) throws
        -> SavingGoalAuthoritativeCloudRow {
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(conflictRequest)) as! [String: Any]
        json["user_id"] = ownerID.uuidString
        json["plan_revision"] = 0
        for (key, value) in changes { json[key] = value }
        return try JSONDecoder().decode(
            SavingGoalAuthoritativeCloudRow.self,
            from: JSONSerialization.data(withJSONObject: json))
    }
    require(try afterRelaunch.recordReadback(
        conflictRow(["title": "Updated elsewhere", "plan_revision": 1]),
        goalID: conflictGoal, ownerID: ownerID,
        authenticatedOwnerID: ownerID
    ) == .conflicted, "Remote goal change requires user review")
    require(try afterRelaunch.all(for: ownerID)[1].observedRevision == 1,
            "Conflict preserves remote revision")
    expectJournal(.userDecisionRequired) {
        try afterRelaunch.discardConflictedAfterUserDecision(
            goalID: conflictGoal, ownerID: ownerID,
            userConfirmedDiscard: false
        )
    }
    require(try afterRelaunch.all(for: ownerID).count == 2,
            "Unapproved conflict discard must not delete data")
    try afterRelaunch.discardConflictedAfterUserDecision(
        goalID: conflictGoal, ownerID: ownerID, userConfirmedDiscard: true
    )
    require(try afterRelaunch.all(for: ownerID).count == 1,
            "Approved conflict discard keeps unrelated verified intent")

    // Malformed per-owner file never becomes an empty queue or deletes A.
    let foreignFile = dir.appendingPathComponent(
        foreignOwner.uuidString.lowercased() + ".json"
    )
    try Data("{\"ownerID\":\"invalid\"}".utf8).write(
        to: foreignFile, options: [.atomic]
    )
    expectJournal(.invalidJournal) {
        _ = try afterRelaunch.all(for: foreignOwner)
    }
    require(try afterRelaunch.all(for: ownerID).count == 1,
            "Corrupted account B is isolated from A")
    // Duplicate IDs inside a file are rejected on reconstruction.
    let ownedFile = dir.appendingPathComponent(
        ownerID.uuidString.lowercased() + ".json"
    )
    let repeated = try JSONEncoder().encode([initial, initial])
    try repeated.write(to: ownedFile, options: [.atomic])
    expectJournal(.invalidJournal) {
        _ = try afterRelaunch.all(for: ownerID)
    }
    // A tampered owner fails closed, even when a file is named for account A.
    var forged = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode([initial])) as! [[String: Any]]
    forged[0]["ownerID"] = foreignOwner.uuidString
    try JSONSerialization.data(withJSONObject: forged).write(
        to: ownedFile, options: [.atomic]
    )
    expectJournal(.invalidJournal) {
        _ = try afterRelaunch.all(for: ownerID)
    }
}
print("PASS: #80 pending first-goal atomic journal, relaunch, conflict, account and corruption gates")

print("PASS: #80 create-only safe insert shape, exact account readback and ambiguity rejection")
'''


class GoalCreateReadbackContractChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = APP_SOURCE.read_text()
        assert cls.source.count(START) == 1
        assert cls.source.count(END) == 1
        cls.contract = cls.source.split(START, 1)[1].split(END, 1)[0]

    def test_unwired_and_not_upsert_or_live_create(self):
        self.assertIn("Dormant insert-only goal", self.contract)
        self.assertNotIn('.insert(request', self.source)
        self.assertNotIn('client.rpc("pipo_apply_plan_revision_v1"', self.source)
        # Existing goal-first UPSERT has intentionally NOT been replaced.
        self.assertIn('.upsert(payloads, onConflict: "id")', self.source)

    def test_static_owner_and_revision_never_in_insert_wire(self):
        block = self.contract.split("struct SavingGoalCreateOnlyRequest:", 1)[1].split(
            "struct SavingGoalAuthoritativeCloudRow:", 1)[0]
        self.assertIn('case goalID = "id"', block)
        self.assertNotIn('case ownerID = "user_id"', block)
        self.assertNotIn('case planRevision = "plan_revision"', block)
        self.assertIn("expectedOwnerID = ownerID", block)
        self.assertIn("PipoGoalCurrency.minorUnits", block)
        self.assertIn("missingOrInvisible", self.contract)
        self.assertIn("remotelyRevised", self.contract)

    def test_swift_insert_and_readback_in_actual_contract(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Linux runner lacks Swift compiler")
        with tempfile.TemporaryDirectory() as folder:
            tmp = Path(folder)
            (tmp / "Contract.swift").write_text(
                FIXTURE + "\n// " + START + self.contract
            )
            (tmp / "main.swift").write_text(HARNESS)
            binary = tmp / "contract"
            result = subprocess.run(
                [swiftc, "-swift-version", "5", "-o", str(binary),
                 str(tmp / "Contract.swift"), str(tmp / "main.swift")],
                text=True, capture_output=True, timeout=90,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            executed = subprocess.run(
                [str(binary)], text=True, capture_output=True, timeout=20
            )
            self.assertEqual(
                executed.returncode, 0, executed.stdout + executed.stderr
            )
            self.assertIn("PASS: #80 create-only", executed.stdout)


if __name__ == "__main__":
    unittest.main()
