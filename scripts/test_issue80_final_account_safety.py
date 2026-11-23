"""Issue #80 integrated privacy and account scope safety gates.

This harness COMPILES and RUNS the actual production WidgetSharedData.swift
with Swift Foundation on Ubuntu (no iOS simulator, no network, no credentials).
Other checks are source invariants, not substitutes for signed iPhone QA.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WIDGET = ROOT / "Pipo/Widget/WidgetSharedData.swift"
DASHBOARD = ROOT / "Pipo/Features/Dashboard/ContentView.swift"
ROOT_VIEW = ROOT / "Pipo/App/RootView.swift"
NETWORK = ROOT / "Pipo/Core/Network/SupabaseService.swift"
MANAGE = ROOT / "Pipo/Features/PersonalSaving/ManagePlanV2.swift"

SWIFT_HARNESS = r"""
import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
let suite = "pipo.widget.isolation.finalqa.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suite) else {
    fatalError("Could not create disposable test suite")
}
defer { defaults.removePersistentDomain(forName: suite) }
let a = UUID(), b = UUID(), id = UUID()
func snapshot(_ userID: UUID?) -> WidgetSnapshot {
    WidgetSnapshot(streakDays: 5, totalXP: 100, currentLevel: 2,
                   goalID: id, goalTitle: "Private A goal",
                   goalProgress: 0.25, nextDepositDate: Date(),
                   ownerUserID: userID, consistencyUnit: "week",
                   recordedCount: 3)
}
WidgetSharedData.activate(userID: a, in: defaults)
try WidgetSharedData.save(snapshot(a), in: defaults)
check(WidgetSharedData.load(from: defaults).goalTitle == "Private A goal",
      "Owner A could not read own widget")
WidgetSharedData.activate(userID: b, in: defaults)
check(WidgetSharedData.load(from: defaults).goalTitle == nil,
      "Owner B read A data")
check(defaults.dictionary(forKey: "pipo.widget.snapshot") == nil,
      "Owner A snapshot physically persisted after switch")
do {
    try WidgetSharedData.save(snapshot(a), in: defaults)
    fatalError("Old-owner save incorrectly succeeded")
} catch WidgetSharedDataError.accountMismatch { }

WidgetSharedData.activate(userID: nil, in: defaults)
do {
    try WidgetSharedData.save(snapshot(nil), in: defaults)
    fatalError("Ownerless sensitive payload persisted")
} catch WidgetSharedDataError.accountMismatch { }

for secret in [
    WidgetSnapshot(streakDays: 0, totalXP: 0, currentLevel: 1,
                   goalID: nil, goalTitle: "Title only",
                   goalProgress: 0, nextDepositDate: nil),
    WidgetSnapshot(streakDays: 0, totalXP: 0, currentLevel: 1,
                   goalID: nil, goalTitle: nil,
                   goalProgress: 0.5, nextDepositDate: nil),
    WidgetSnapshot(streakDays: 0, totalXP: 0, currentLevel: 1,
                   goalID: nil, goalTitle: nil,
                   goalProgress: 0, nextDepositDate: Date()),
    WidgetSnapshot(streakDays: 0, totalXP: 0, currentLevel: 1,
                   goalID: nil, goalTitle: nil,
                   goalProgress: 0, nextDepositDate: nil,
                   consistencyUnit: "day", recordedCount: 0),
    WidgetSnapshot(streakDays: 0, totalXP: 0, currentLevel: 1,
                   goalID: nil, goalTitle: nil,
                   goalProgress: 0, nextDepositDate: nil,
                   consistencyUnit: nil, recordedCount: 1),
] {
    do {
        try WidgetSharedData.save(secret, in: defaults)
        fatalError("Ownerless private snapshot accepted")
    } catch WidgetSharedDataError.accountMismatch { }
}
check(defaults.dictionary(forKey: "pipo.widget.snapshot") == nil,
      "Unowned snapshot leaked App Group data")

// Legacy migration: stale snapshot with missing active-account marker.
defaults.set(["ownerUserID": a.uuidString, "goalTitle": "Old secret"],
             forKey: "pipo.widget.snapshot")
defaults.removeObject(forKey: "pipo.widget.active.account")
WidgetSharedData.activate(userID: nil, in: defaults)
check(defaults.dictionary(forKey: "pipo.widget.snapshot") == nil,
      "Logout failed to purge legacy private data")
try WidgetSharedData.save(.empty, in: defaults)
check(defaults.dictionary(forKey: "pipo.widget.snapshot") == nil,
      "Empty snapshot should not retain a private persisted record")

WidgetSharedData.activate(userID: a, in: defaults)
try WidgetSharedData.save(snapshot(a), in: defaults)
WidgetSharedData.activate(userID: nil, in: defaults)
check(WidgetSharedData.load(from: defaults).goalID == nil,
      "Logout did not clear visible widget")
check(defaults.dictionary(forKey: "pipo.widget.snapshot") == nil,
      "Logout did not erase private widget data")
print("PASS real Swift WidgetSharedData: A/B, stale owner, physical purge, ownerless payload guards")
"""

class Issue80FinalAccountSafety(unittest.TestCase):
    def test_swift_account_switch_and_widget_persistence(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("Swift toolchain unavailable; required GitHub Ubuntu job has swiftc")
        with tempfile.TemporaryDirectory(prefix="pipo-qa-") as temp:
            path = Path(temp)
            (path / "main.swift").write_text(SWIFT_HARNESS)
            subprocess.run(
                [swiftc, str(WIDGET), str(path / "main.swift"),
                 "-o", str(path / "isolation")],
                check=True, capture_output=True, text=True, timeout=90,
            )
            p = subprocess.run(
                [str(path / "isolation")], check=True, capture_output=True,
                text=True, timeout=20,
            )
            self.assertIn("PASS real Swift WidgetSharedData", p.stdout)

    def test_dashboard_account_change_resets_all_ephemeral_financial_ui(self):
        source = DASHBOARD.read_text()
        block = source.split('.onChange(of: authStateManager.userID) { _, _ in', 1)[1].split(
            '\n        .sheet(', 1)[0]
        for field in ('isShowingSaveConfirmation = false',
                      'goalToRecord = nil', 'savingAmount = ""',
                      'savingInlineError = nil', 'savingInlineErrorFocused = false',
                      'saveErrorMessage = nil', 'completedSavingReward = nil',
                      'selectedGroupGoal = nil', 'selectedPage = .home'):
            self.assertIn(field, block)

    def test_active_account_guard_before_personal_sync_and_widget_navigation(self):
        root = ROOT_VIEW.read_text()
        self.assertIn("authStateManager.userID == userID", root)
        self.assertIn("AccountScope.visibleGoals(allGoals, userID: userID)", root)
        self.assertIn("AccountScope.visibleTransactions(", root)
        self.assertIn("AccountScope.canOpenWidgetSavingRequest(", root)
        self.assertIn("navigationManager.resetAccountContext()", root)
        self.assertIn("updateWidgetAccount(userID)", root)
        self.assertIn("WidgetCenter.shared.reloadAllTimelines()", root)

    def test_staged_cas_and_money_out_still_fail_closed(self):
        network = NETWORK.read_text()
        ui = MANAGE.read_text()
        self.assertIn("#if PIPO_ISSUE80_STAGING", network)
        self.assertIn("#if PIPO_ISSUE80_BRIDGE", network)
        self.assertIn("SavingPlanBudgetV2IntentJournal", network)
        self.assertIn("SavingPlanBudgetV2ReceiptValidator", network)
        self.assertIn("A secure save isn't available yet.", ui)
        self.assertIn("Saving unavailable", ui)
        self.assertNotIn("PIPO_ISSUE80_STAGING = YES", (ROOT / "Pipo.xcodeproj/project.pbxproj").read_text())

    def test_ax3_320_nav_header_remains_single_line_and_accessible(self):
        ui = MANAGE.read_text()
        bar = ui.split("    private var topBar: some View {", 1)[1].split(
            "    @ViewBuilder", 1)[0]
        self.assertIn("dynamicTypeSize.isAccessibilitySize", bar)
        self.assertIn('Image(systemName: "chevron.left")', bar)
        self.assertIn('.accessibilityLabel("Back")', bar)
        self.assertIn('.accessibilityLabel("Manage plan")', bar)
        self.assertIn('.lineLimit(1)', bar)
        self.assertIn('.minimumScaleFactor(0.65)', bar)
        self.assertIn('.frame(minWidth: 58, minHeight: 48', bar)

if __name__ == "__main__":
    unittest.main()
