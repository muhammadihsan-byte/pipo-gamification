"""Compile and exercise the actual #80 Swift contract on Linux, no Xcode.

The extraction is intentionally bounded to an isolated Foundation-only block
inside SupabaseService.swift. We substitute a minimal currency fixture ONLY
because PipoGoalCurrency.swift imports app-specific SwiftUI support. This
validates Swift syntax, Codable wire shape, Decimal amounts and receipt guards,
not the iOS app or real database.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "Pipo/Core/Network/SupabaseService.swift"
START = "// MARK: - #80: Inactive, server-revisioned Manage Plan contract"
END = "enum SavingMoneyOutRequestError: Error, Equatable {"

FIXTURE = r"""
import Foundation

// Synthetic currency adapter used only for the Linux contract harness.
enum PipoGoalCurrency {
    static func isSupported(_ code: String) -> Bool {
        ["IDR", "USD", "JPY"].contains(code)
    }
    static func decimal(_ minor: Int64, code: String) -> Decimal {
        Decimal(minor) / Decimal(code == "USD" ? 100 : 1)
    }
    static func minorUnits(_ amount: Decimal, code: String,
                           allowZero: Bool = false) -> Int64? {
        guard isSupported(code), amount >= 0,
              amount <= Decimal(string: "9999999999999.99")!,
              allowZero || amount > 0 else { return nil }
        let scaled = amount * Decimal(code == "USD" ? 100 : 1)
        let number = NSDecimalNumber(decimal: scaled)
        guard number.decimalValue == scaled,
              let exact = Int64(number.stringValue),
              allowZero || exact > 0
        else { return nil }
        return exact
    }
}
"""

HARNESS = r"""
import Foundation

func check(_ valid: Bool, _ message: String) {
    if !valid { fatalError(message) }
}

let requestID = UUID()
let goalID = UUID()
let request = try SavingPlanCASRequest(
    requestID: requestID, goalID: goalID, expectedRevision: 0,
    targetMinorUnits: 30, currencyCode: "USD",
    targetDate: Date(timeIntervalSince1970: 1_800_000_000),
    rhythm: "weekly", preferredSavingDay: 2,
    plannedContributionMinorUnits: 10
)
check(request.targetAmount == Decimal(string: "0.30")!, "Decimal USD target")
check(request.plannedContributionOverride == Decimal(string: "0.10")!, "Decimal contribution")
let data = try JSONEncoder().encode(request)
let wire = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let requiredKeys: Set<String> = [
    "p_request_id", "p_goal_id", "p_expected_revision",
    "p_target_amount", "p_target_date", "p_rhythm",
    "p_preferred_saving_day", "p_planned_contribution_override"
]
check(Set(wire.keys) == requiredKeys, "Exact RPC keys: \(wire.keys)")
check(wire["p_user_id"] == nil && wire["p_currency_code"] == nil,
      "No client-supplied owner or currency mutation")
let flex = try SavingPlanCASRequest(
    requestID: UUID(), goalID: goalID, expectedRevision: 0,
    targetMinorUnits: 6_000_000, currencyCode: "IDR",
    targetDate: Date(timeIntervalSince1970: 1_800_000_000),
    rhythm: "flexible", preferredSavingDay: nil,
    plannedContributionMinorUnits: nil
)
let flexWire = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(flex)
) as! [String: Any]
check(flexWire["p_preferred_saving_day"] is NSNull, "Null day must be present")
check(flexWire["p_planned_contribution_override"] is NSNull, "Null amount present")
do {
    _ = try SavingPlanCASRequest(
        requestID: UUID(), goalID: goalID, expectedRevision: -1,
        targetMinorUnits: 30, currencyCode: "USD",
        targetDate: .now, rhythm: "weekly", preferredSavingDay: 2,
        plannedContributionMinorUnits: 10
    )
    fatalError("Negative revision accepted")
} catch SavingPlanCASContractError.invalidRevision {}

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
let reply = try decode(applied)
let outcome = try SavingPlanCASReceiptValidator.verify(reply, for: request)
check(outcome == .applied(requestID: requestID, acceptedRevision: 1),
      "Verified receipt")
let conflict = try decode(
    "{\"status\":\"conflict\",\"goal_id\":\"\(goalID.uuidString)\",\"current_revision\":2}"
)
check(try SavingPlanCASReceiptValidator.verify(conflict, for: request)
    == .conflict(currentRevision: 2), "Conflict remains explicit")
for corrupted in [
    applied.replacingOccurrences(of: "\"currency_code\":\"USD\"",
                                 with: "\"currency_code\":\"IDR\""),
    applied.replacingOccurrences(of: "\"target_amount\":0.30",
                                 with: "\"target_amount\":0.31"),
    applied.replacingOccurrences(of: "\"accepted_revision\":1",
                                 with: "\"accepted_revision\":99"),
    applied.replacingOccurrences(of: goalID.uuidString,
                                 with: UUID().uuidString)
] {
    do {
        _ = try SavingPlanCASReceiptValidator.verify(
            decode(corrupted), for: request
        )
        fatalError("Corrupted receipt accepted")
    } catch SavingPlanCASContractError.invalidServerResponse {}
}
print("PASS: #80 Swift exact-decimal CAS request, explicit null, conflict and receipt guards")
"""


class ClientContractChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = APP_SOURCE.read_text()
        assert cls.source.count(START) == 1
        assert cls.source.count(END) == 1
        cls.block = cls.source.split(START, 1)[1].split(END, 1)[0]

    def test_off_by_default_and_no_live_rpc_call(self):
        self.assertIn("deliberately NOT wired", self.source)
        self.assertNotIn('client.rpc("pipo_apply_plan_revision_v1"', self.source)
        self.assertIn('.from("saving_goals")', self.source)
        self.assertIn('.upsert(payloads, onConflict: "id")', self.source)

    def test_currency_and_identity_never_sent_to_rpc(self):
        self.assertIn('case goalID = "p_goal_id"', self.block)
        self.assertIn('case requestID = "p_request_id"', self.block)
        self.assertNotIn('case userID = "p_user_id"', self.block)
        self.assertNotIn('case currencyCode = "p_currency_code"', self.block)
        self.assertIn("expectedRevision + 1", self.block)

    def test_linux_swift_contract_compilation_and_runtime(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Swift compiler not installed on this Linux runner")
        with tempfile.TemporaryDirectory() as folder:
            tmp = Path(folder)
            (tmp / "Contract.swift").write_text(
                FIXTURE + "\n// " + START + self.block
            )
            (tmp / "main.swift").write_text(HARNESS)
            binary = tmp / "contract"
            proc = subprocess.run(
                [swiftc, "-swift-version", "5", "-o", str(binary),
                 str(tmp / "Contract.swift"), str(tmp / "main.swift")],
                text=True, capture_output=True, timeout=90,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            run = subprocess.run(
                [str(binary)], text=True, capture_output=True, timeout=20
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS: #80 Swift", run.stdout)


if __name__ == "__main__":
    unittest.main()
