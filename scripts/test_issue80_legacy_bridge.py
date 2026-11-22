"""Issue #80 legacy-schema signed bridge candidate: compile current Swift contracts.

No app signing, no live REST, no paid staging, no migrations. The bridge flag
is disabled for all product builds; this harness validates durable recovery.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from scripts.test_issue80_client_contract import APP_SOURCE, START, END, FIXTURE

HARNESS = r'''
import Foundation

func check(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
}
func reject(_ expected: LegacyGoalBridgeError, _ action: () throws -> Void) {
    do { try action(); fatalError("Expected fail-closed error \(expected)") }
    catch let error as LegacyGoalBridgeError {
        check(error == expected, "wrong error \(error)")
    } catch { fatalError("unexpected error \(error)") }
}
let owner = UUID(), foreign = UUID(), goal = UUID()
let began = Date(timeIntervalSince1970: 1_800_000_000)
let target = Date(timeIntervalSince1970: 1_810_000_000)
let request = try SavingGoalCreateOnlyRequest(
    goalID: goal, ownerID: owner, title: " Camera ", category: "gadget",
    customCategory: nil, targetMinorUnits: 100,
    currencyCode: "USD", startDate: began, targetDate: target,
    rhythm: "weekly", preferredSavingDay: 3,
    plannedContributionMinorUnits: 25
)
func cloud(_ changes: [String: Any] = [:]) throws -> LegacyGoalBridgeCloudRow {
    var dictionary = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(request)
    ) as! [String:Any]
    dictionary["user_id"] = owner.uuidString
    for (key, value) in changes { dictionary[key] = value }
    return try JSONDecoder().decode(
        LegacyGoalBridgeCloudRow.self,
        from: JSONSerialization.data(withJSONObject: dictionary)
    )
}
let saved = try cloud()
try LegacyGoalBridgeReadbackVerifier.verify(
    saved, request: request, authenticatedOwnerID: owner)
reject(.pendingConfirmation) {
    try LegacyGoalBridgeReadbackVerifier.verify(
        nil, request: request, authenticatedOwnerID: owner)
}
reject(.accountChanged) {
    try LegacyGoalBridgeReadbackVerifier.verify(
        saved, request: request, authenticatedOwnerID: foreign)
}
reject(.untrustedReadback) {
    try LegacyGoalBridgeReadbackVerifier.verify(
        cloud(["user_id":foreign.uuidString]),
        request: request, authenticatedOwnerID: owner)
}
let mismatches: [[String:Any]] = [
    ["target_amount":1.01],
    ["title":"Other camera"],
    ["currency_code":"JPY"],
    ["rhythm":"daily"],
    ["preferred_saving_day":4],
    ["target_date":"2028-01-01T00:00:00Z"]
]
for differences in mismatches {
    reject(.cloudConflict) {
        try LegacyGoalBridgeReadbackVerifier.verify(
            cloud(differences), request: request, authenticatedOwnerID: owner)
    }
}
let encoded = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(request)) as! [String: Any]
check(encoded["user_id"] == nil, "INSERT must never spoof owner")
check(encoded["plan_revision"] == nil, "Legacy bridge cannot fake revision")
let storage = FileManager.default.temporaryDirectory
    .appendingPathComponent("pipo-legacy-bridge-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: storage) }
let journal = LegacyGoalBridgeIntentJournal(directory: storage)
let stage = try journal.stage(request, ownerID: owner)
check(stage.state == .staged, "First create is persisted before network")
check(try journal.stage(request, ownerID: owner) == stage,
      "Stable UUID and full original request across exact replay")
reject(.accountChanged) { _ = try journal.stage(request, ownerID: foreign) }
let altered = try SavingGoalCreateOnlyRequest(
    goalID: goal, ownerID: owner, title: "Different",
    category: "gadget", customCategory: nil,
    targetMinorUnits: 100, currencyCode: "USD",
    startDate: began, targetDate: target, rhythm: "weekly",
    preferredSavingDay: 3, plannedContributionMinorUnits: 25)
reject(.cloudConflict) { _ = try journal.stage(altered, ownerID: owner) }
try journal.markAttempted(goalID: goal, ownerID: owner)
let reopened = LegacyGoalBridgeIntentJournal(directory: storage)
check(try reopened.intent(goalID: goal, ownerID: owner)?.state == .attempted,
      "Crash/relaunch retains uncertain INSERT state")
reject(.pendingConfirmation) {
    try reopened.markAttempted(goalID: goal, ownerID: owner)
}
check(try reopened.all(for: foreign).isEmpty,
      "Unrelated account cannot see owner journal")
reject(.cloudConflict) {
    try reopened.recordVerifiedReadback(try cloud(["target_amount":0.99]),
        goalID: goal, ownerID: owner, authenticatedOwnerID: owner)
}
check(try reopened.intent(goalID: goal, ownerID: owner)?.state == .attempted,
      "Conflicting readback never drops original journal")
reject(.accountChanged) {
    try reopened.recordVerifiedReadback(saved,
        goalID: goal, ownerID: owner, authenticatedOwnerID: foreign)
}
try reopened.recordVerifiedReadback(saved, goalID: goal,
                                    ownerID: owner, authenticatedOwnerID: owner)
check(try reopened.intent(goalID: goal, ownerID: owner)?.state == .verified,
      "Only exact authenticated readback verifies, no CAS revision")
try reopened.recordVerifiedReadback(saved, goalID: goal,
                                    ownerID: owner, authenticatedOwnerID: owner)
check(try LegacyGoalBridgeIntentJournal(directory: storage)
        .intent(goalID: goal, ownerID: owner)?.state == .verified,
      "Verified UUID preserved across relaunch")
reject(.cloudConflict) { _ = try reopened.stage(altered, ownerID: owner) }
let path = storage.appendingPathComponent(owner.uuidString.lowercased() + ".json")
try Data("{tampered".utf8).write(to: path, options:[.atomic])
reject(.invalidJournal) { _ = try reopened.all(for: owner) }
print("PASS: signed bridge legacy schema, fresh readback, UUID recovery and owner isolation")
'''

class LegacyGoalBridgeChecks(unittest.TestCase):
    def test_bridge_is_explicitly_unshipped_and_does_not_require_revision(self):
        body = APP_SOURCE.read_text()
        self.assertIn("#if PIPO_ISSUE80_BRIDGE", body)
        self.assertIn("issue80BridgeLegacyGoals(", body)
        self.assertIn('case goalID = "id"', body)
        bridge = body.split("// MARK: - #80: Candidate legacy-schema signed bridge", 1)[1].split(
            "// MARK: - #80: Pure local reconcile decision", 1)[0]
        self.assertIn("LegacyGoalBridgeCloudRow", bridge)
        self.assertNotIn('planRevision = "plan_revision"', bridge)
        adapter = body.split("private func issue80BridgeLegacyGoals", 1)[1].split(
            "    #endif", 1
        )[0]
        self.assertIn("issue80BridgeFetchOwnedLegacyGoal", adapter)
        self.assertIn("issue80BridgeInsertGoalOnly", adapter)
        self.assertIn('client.from("saving_goals")', adapter)
        self.assertIn(".insert(request)", adapter)
        self.assertNotIn(".upsert(", adapter)
        self.assertNotIn(".update(", adapter)
        self.assertIn("LegacyGoalBridgeError.pendingConfirmation", adapter)
        self.assertIn("LegacyGoalBridgeIntentJournal.inApplicationSupport()", adapter)
        self.assertIn('client.auth.currentUser?.id == authenticatedUserID', adapter)
        self.assertIn("No auto retry if INSERT timed out", bridge)

    def test_compiled_swift_bridge_fails_closed_with_disk_recovery(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Swift compiler not present; Ubuntu CI uses Swift")
        source = APP_SOURCE.read_text()
        self.assertEqual(source.count(START), 1)
        self.assertEqual(source.count(END), 1)
        isolated = source.split(START, 1)[1].split(END, 1)[0]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "Contract.swift").write_text(FIXTURE + "\n" + isolated)
            (root / "main.swift").write_text(
                "import Foundation\ntry MainActor.assumeIsolated {\n"
                + HARNESS.split("import Foundation", 1)[1] + "\n}\n"
            )
            binary = root / "legacy-bridge"
            compiled = subprocess.run(
                [swiftc, "-swift-version", "5", "-o", str(binary),
                 str(root / "Contract.swift"), str(root / "main.swift")],
                capture_output=True, text=True, timeout=90
            )
            self.assertEqual(compiled.returncode, 0,
                             compiled.stdout + compiled.stderr)
            ran = subprocess.run([str(binary)], capture_output=True,
                                 text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertIn("PASS: signed bridge legacy schema", ran.stdout)


if __name__ == "__main__":
    unittest.main()
