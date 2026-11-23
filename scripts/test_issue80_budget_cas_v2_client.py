"""#80 atomic budget-CAS V2: compiled Swift contract + review-only SQL invariant QA.

Linux builds the extracted PRODUCTION Foundation-only Swift type declarations;
it does not compile the native app nor enable a Supabase network write.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from scripts.test_issue80_client_contract import APP_SOURCE, FIXTURE, ROOT

BEGIN = "// MARK: - #80: Dormant *atomic* target + budget CAS V2 wire contract"
END = "// MARK: - #80: Dormant insert-only goal and authoritative readback contract"
SQL = ROOT / "supabase/proposals/issue_80_budget_cas_v2_REVIEW_ONLY.sql"

SWIFT = r'''
import Foundation

func check(_ good: Bool, _ reason: String) {
    if !good { fatalError(reason) }
}
func expectFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        fatalError("Invalid state accepted")
    } catch is SavingPlanBudgetV2ContractError {
        // Typed failure is required; no generic network/JSON exception.
    } catch {
        fatalError("Unexpected error type: \(error)")
    }
}
let user = UUID(), goal = UUID(), transaction = UUID()
let rows = try [
    SavingPlanBudgetV2Item(
        id: UUID(), title: "  Transport  ", minorUnits: 60,
        currencyCode: "USD", isCompleted: false),
    SavingPlanBudgetV2Item(
        id: UUID(), title: "Hotel", minorUnits: 40,
        currencyCode: "USD", isCompleted: true)
]
let target = Date(timeIntervalSince1970: 1_800_000_000)
let request = try SavingPlanBudgetV2Request(
    requestID: transaction, goalID: goal, expectedRevision: 0,
    ownerID: user, currencyCode: "USD", targetMinorUnits: 100,
    targetDate: target, rhythm: "weekly", preferredSavingDay: 3,
    plannedContributionMinorUnits: 25, items: rows,
    cloudBudgetNeedsReview: true, userReviewedBudget: true
)
check(request.targetAmount == Decimal(string: "1.00")!, "USD exact target")
check(request.items[0].title == "Transport", "Trimmed item title")
let encoded = try JSONEncoder().encode(request)
let wire = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
let columns: Set<String> = [
    "p_request_id","p_goal_id","p_expected_revision",
    "p_target_amount","p_target_date","p_rhythm",
    "p_preferred_saving_day","p_planned_contribution_override",
    "p_items","p_budget_import_confirmed"
]
check(Set(wire.keys) == columns, "Only allowed atomic CAS params")
check(wire["p_user_id"] == nil && wire["p_currency_code"] == nil,
      "No client supplied Auth owner or mutable currency")
check(wire["p_budget_import_confirmed"] as? Bool == true,
      "Budget review explicitly confirmed")
let items = wire["p_items"] as! [[String:Any]]
check(items.count == 2, "Whole budget must travel atomically")
check(Set(items[0].keys) == ["id", "title", "amount", "is_completed"],
      "Exact private budget item keys")
check(items[0]["amount"] as? NSNumber == NSNumber(value: 0.6),
      "Stored minor cents converted to exact major units")
check(items[1]["is_completed"] as? Bool == true,
      "Preserve completed budget metadata without XP effect")
func makeResponse(_ edits:[String:Any] = [:]) throws
    -> SavingPlanBudgetV2WireResponse {
    var body:[String:Any] = [
        "status":"applied","request_id":transaction.uuidString,
        "goal_id":goal.uuidString,"currency_code":"USD",
        "accepted_revision":1,"budget_snapshot_state":"synced",
        "target_amount":wire["p_target_amount"]!,
        "target_date":wire["p_target_date"]!,
        "rhythm":"weekly","preferred_saving_day":3,
        "planned_contribution_override":wire["p_planned_contribution_override"]!,
        "items":items
    ]
    for (key,value) in edits { body[key] = value }
    let data = try JSONSerialization.data(withJSONObject: body)
    return try JSONDecoder().decode(SavingPlanBudgetV2WireResponse.self, from:data)
}
let applied = try makeResponse()
check(try SavingPlanBudgetV2ReceiptValidator.verify(applied,for:request)
   == .applied(requestID:transaction,revision:1), "Verified exact budget receipt")
for changed in [
    ["accepted_revision":5],
    ["goal_id":UUID().uuidString],
    ["request_id":UUID().uuidString],
    ["currency_code":"JPY"],
    ["budget_snapshot_state":"needs_review"],
    ["target_amount":1.01],
    ["preferred_saving_day":4],
    ["rhythm":"monthly"],
    ["target_date":"2030-01-01T00:00:00Z"]
] {
    expectFailure {
        _ = try SavingPlanBudgetV2ReceiptValidator.verify(
            makeResponse(changed),for:request)
    }
}
var altered = items
altered[0]["amount"] = 0.59
expectFailure {
    _ = try SavingPlanBudgetV2ReceiptValidator.verify(
        makeResponse(["items":altered]),for:request)
}
var reordered = items
reordered.reverse()
expectFailure {
    _ = try SavingPlanBudgetV2ReceiptValidator.verify(
        makeResponse(["items":reordered]),for:request)
}
let conflict = try JSONDecoder().decode(
    SavingPlanBudgetV2WireResponse.self,
    from: Data(
        "{\"status\":\"conflict\",\"goal_id\":\"\(goal.uuidString)\",\"current_revision\":3}".utf8
    )
)
check(try SavingPlanBudgetV2ReceiptValidator.verify(conflict,for:request)
    == .conflict(currentRevision:3), "No automatic rebase")
expectFailure {
    _ = try SavingPlanBudgetV2Request(
        requestID:UUID(),goalID:goal,expectedRevision:0,
        ownerID:user,currencyCode:"USD",targetMinorUnits:100,
        targetDate:target,rhythm:"weekly",preferredSavingDay:3,
        plannedContributionMinorUnits:25,items:rows,
        cloudBudgetNeedsReview:true,userReviewedBudget:false)
}
let duplicate = [rows[0], rows[0]]
expectFailure {
    _ = try SavingPlanBudgetV2Request(
        requestID:UUID(),goalID:goal,expectedRevision:0,
        ownerID:user,currencyCode:"USD",targetMinorUnits:120,
        targetDate:target,rhythm:"weekly",preferredSavingDay:3,
        plannedContributionMinorUnits:25,items:duplicate,
        cloudBudgetNeedsReview:false,userReviewedBudget:false)
}
expectFailure {
    _ = try SavingPlanBudgetV2Request(
        requestID:UUID(),goalID:goal,expectedRevision:0,
        ownerID:user,currencyCode:"USD",targetMinorUnits:101,
        targetDate:target,rhythm:"weekly",preferredSavingDay:3,
        plannedContributionMinorUnits:25,items:rows,
        cloudBudgetNeedsReview:false,userReviewedBudget:false)
}
let flexible = try SavingPlanBudgetV2Request(
    requestID: UUID(), goalID: goal, expectedRevision: 0, ownerID: user,
    currencyCode: "IDR", targetMinorUnits: 5000, targetDate: target,
    rhythm: "flexible", preferredSavingDay: nil,
    plannedContributionMinorUnits: nil, items: [],
    cloudBudgetNeedsReview: false, userReviewedBudget: false
)
let flex = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(flexible)) as! [String:Any]
check(flex["p_items"] is [Any], "Empty budget must be explicit array")
check(flex["p_preferred_saving_day"] is NSNull, "Null cadence day explicit")
check(flex["p_planned_contribution_override"] is NSNull,
      "Null future contribution explicit")
print("PASS: #80 Swift budget CAS V2 atomic target/rows, exact decimals, user review and forged receipt rejects")
'''

class BudgetCASV2Checks(unittest.TestCase):
    def test_sql_is_review_only_and_keeps_old_clients_blocked(self):
        t = SQL.read_text()
        self.assertIn("REVIEW ONLY", t)
        self.assertIn("REVOKE EXECUTE ON FUNCTION public.pipo_apply_plan_revision_v1(", t)
        self.assertIn("budget_snapshot_state text NOT NULL DEFAULT 'needs_review'", t)
        self.assertIn("BEFORE INSERT ON public.saving_goals", t)
        self.assertIn("private.pipo_plan_budget_items_v2", t)
        self.assertIn("private.pipo_plan_budget_receipts_v2", t)
        self.assertIn("pipo_read_plan_budget_v2", t)
        self.assertIn("budget_import_confirmed", t)
        self.assertIn("FOR UPDATE", t)
        self.assertIn("REVOKE ALL ON private.pipo_plan_budget_items_v2", t)
        self.assertIn("REVOKE ALL ON FUNCTION public.pipo_apply_plan_budget_v2(", t)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.pipo_apply_plan_budget_v2(", t)
        self.assertIn("RETURN v_existing.result_snapshot", t)
        self.assertIn("p_items IS NULL", t)
        self.assertIn("v_budget_total <> p_target_amount", t)
        self.assertNotIn("DROP TABLE public.saving_transactions", t)

    def test_client_contract_is_dormant_and_encodes_no_owner(self):
        s = APP_SOURCE.read_text()
        segment = s.split(BEGIN,1)[1].split(END,1)[0]
        self.assertIn('case items = "p_items"', segment)
        self.assertIn('case budgetImportConfirmed = "p_budget_import_confirmed"', segment)
        self.assertNotIn('case expectedOwnerID = "p_user_id"', segment)
        self.assertNotIn('case currencyCode = "p_currency_code"', segment)
        self.assertNotIn('client.rpc("pipo_apply_plan_budget_v2"', s)

    def test_compiled_production_swift_request_and_receipt(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Linux Swift compiler unavailable")
        source = APP_SOURCE.read_text()
        self.assertEqual(source.count(BEGIN),1)
        self.assertEqual(source.count(END),1)
        only = source.split(BEGIN,1)[1].split(END,1)[0]
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)
            (work/"Contract.swift").write_text(FIXTURE+"\n"+only)
            (work/"main.swift").write_text(SWIFT)
            bin = work/"contract"
            result = subprocess.run(
                [swiftc, "-swift-version","5", "-o",str(bin),
                 str(work/"Contract.swift"),str(work/"main.swift")],
                capture_output=True,text=True,timeout=90)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            execute = subprocess.run([str(bin)],capture_output=True,
                                     text=True,timeout=30)
            self.assertEqual(execute.returncode,0,execute.stdout+execute.stderr)
            self.assertIn("PASS: #80 Swift budget CAS V2",execute.stdout)

if __name__=="__main__":
    unittest.main()
