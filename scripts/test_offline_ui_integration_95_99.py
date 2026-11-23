#!/usr/bin/env python3
"""Offline source-level integration gate for PR #95 + offline UI #96-#99.

These assertions protect cross-branch composition and navigation safety.
They are NOT native build, screenshot or VoiceOver validation.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
def read(name):
    return (ROOT / name).read_text()

DASH = read("Pipo/Features/Dashboard/ContentView.swift")
ROOT_VIEW = read("Pipo/App/RootView.swift")
NAV = read("Pipo/Core/Navigation/NavigationManager.swift")
GOAL = read("Pipo/Features/PersonalSaving/ReviewPlanView.swift")
CREATE = read("Pipo/Features/PersonalSaving/CreateGoalView.swift")
MILESTONE = read("Pipo/Features/Gamification/ConsistencyMilestoneView.swift")
SPARK = read("Pipo/Core/DesignSystem/PipoSparkV1.swift")
CARDS = read("Pipo/Core/DesignSystem/PipoApprovedCards.swift")
MASCOT = read("Pipo/Core/DesignSystem/PipoMascotView.swift")
GAMIFICATION = read("Pipo/Core/Gamification/GamificationManager.swift")
GAME_TESTS = read("PipoTests/GamificationManagerTests.swift")
GOAL_TESTS = read("PipoTests/PersonalGoalTests.swift")
WORKFLOW = read(".github/workflows/pr-fast-checks.yml")

class CrossBranchUIContract(unittest.TestCase):
    def test_five_approved_feature_surfaces_present(self):
        for marker, content in (
            ("PipoJourneyWaveAView", CARDS),
            ("PipoSparkPeriodHistoryView", SPARK),
            ("PipoV4ApprovedPose", MASCOT),
            ("PipoFirstSparkEligibility", GAMIFICATION),
            ("private var flexibleReview: some View", GOAL),
            ("pipo.flex.v2.savingHistory", GOAL)
        ):
            self.assertIn(marker, content, marker)

    def test_manual_first_saving_navigation_returns_to_dashboard_before_request(self):
        start = ROOT_VIEW.index("onRecordFirst: { goalID in")
        end = ROOT_VIEW.index("case .personalGoal(", start)
        callback = ROOT_VIEW[start:end]
        self.assertLess(callback.index("navigationManager.popToRoot()"),
                        callback.index("navigationManager.requestDeposit(goalID: goalID)"))
        self.assertIn("authStateManager.userID != nil", callback)
        self.assertIn("onRecordFirst: onRecordFirst", CREATE)
        self.assertIn('Button("Record a saving") { onRecordFirst(goalID) }', GOAL)
        self.assertIn("navigationManager.pendingDepositGoalID", DASH)
        self.assertIn("ownedGoals.map(\\.id)", DASH)
        self.assertIn("AccountScope.owns(goal, userID: ownerID)", DASH)
        self.assertIn("guard let goal = ownedGoals.first", DASH)

    def test_saving_commit_cannot_be_replaced_by_visual_reward(self):
        start = DASH.index("private func confirmSaving()")
        end = DASH.index("private func openPendingDepositRequest()", start)
        code = DASH[start:end]
        self.assertIn("try modelContext.save()", code)
        self.assertLess(code.index("try modelContext.save()"),
                        code.index("PipoFirstSparkEligibility.forCommittedFirstPeriod("))
        self.assertLess(code.index("PipoFirstSparkEligibility.forCommittedFirstPeriod("),
                        code.index("completedSavingReward = ("))
        self.assertIn("transaction.userID == ownerID", GAMIFICATION)
        self.assertIn("goal.ownerUserID == ownerID", GAMIFICATION)
        self.assertIn("goal.rhythm != .flexible", GAMIFICATION)
        self.assertIn("milestoneFirstSparkEligible = false", NAV)
        self.assertIn("firstSparkEligible: false, // legacy navigation", ROOT_VIEW)

    def test_account_owned_journey_and_periods_do_not_claim_bank_balances(self):
        self.assertIn("ownedTransactions", DASH)
        self.assertIn("PipoJourneyWaveAView", DASH)
        self.assertIn("PipoSparkPeriodHistoryView(", GOAL)
        self.assertIn("transactions: ownedHistory(for: goal)", GOAL)
        self.assertIn("goal.rhythm != .flexible", GOAL)
        self.assertIn('flexibleReviewRow("Saving dates", value: "Not scheduled")', GOAL)
        self.assertIn('pipo.flex.v2.manualPace', DASH)
        self.assertIn("AccountScope.owns(goal, userID: authStateManager.userID)", GOAL)

    def test_mobile_sheets_scroll_below_safe_area_actions(self):
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", DASH)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", MILESTONE)
        self.assertIn("ScrollView {", MILESTONE)
        self.assertIn("private func flexiblePlanReady(goalID: UUID)", GOAL)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", GOAL)
        self.assertIn("accessibilityReduceMotion", MILESTONE)

    def test_all_native_regressions_are_retained_once(self):
        required = (
            "testIssue70PeriodHistoryOnlyUsesGoalOwnedScheduledWindows",
            "testFirstSparkOnlyAfterFirstOwnedScheduledContribution",
            "testFirstSparkRejectsCrossAccountFlexibleGroupInvalidAndFutureEntries",
            "testFirstSparkPresentationStateClearsOnAccountSwitch",
            "testFlexibleV2ReturningGoalPreservesFractionalManualProgress",
            "testFlexibleV2OneManualContributionReachesQuarterWithoutStreak"
        )
        for method in required:
            text = GOAL_TESTS if method.startswith("testFlexible") else GAME_TESTS
            self.assertEqual(
                len(re.findall(r"\\bfunc\\s+" + re.escape(method) + r"\\s*\\(", text)),
                1,
                "Missing or duplicated XCTest: " + method
            )

    def test_all_linux_guards_retained_in_same_ci(self):
        for name in (
            "test_accessibility_action_targets.py",
            "test_issue70_ui_slicing_contract.py",
            "test_issue72_first_spark_contract.py",
            "test_flexible_v2_ui_contract.py",
            "test_offline_ui_integration_95_99.py"
        ):
            self.assertIn(name, WORKFLOW, "Lost Linux QA gate: " + name)

if __name__ == "__main__":
    unittest.main()
