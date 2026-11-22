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
