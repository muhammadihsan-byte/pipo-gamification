#!/usr/bin/env python3
"""#72 source contract. This is NOT a native Xcode/rendering test."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
GATE = (ROOT / "Pipo/Core/Gamification/GamificationManager.swift").read_text()
DASH = (ROOT / "Pipo/Features/Dashboard/ContentView.swift").read_text()
ROOT_VIEW = (ROOT / "Pipo/App/RootView.swift").read_text()
NAV = (ROOT / "Pipo/Core/Navigation/NavigationManager.swift").read_text()
MOTION = (ROOT / "Pipo/Features/Gamification/ConsistencyMilestoneView.swift").read_text()
TESTS = (ROOT / "PipoTests/GamificationManagerTests.swift").read_text()


class FirstSparkOfflineContract(unittest.TestCase):
    def test_event_gate_is_owner_goal_and_period_scoped(self):
        self.assertIn("enum PipoFirstSparkEligibility", GATE)
        for token in (
            "goal.ownerUserID == ownerID", "transaction.userID == ownerID",
            "transaction.goalId == goal.id", "goal.rhythm != .flexible",
            "!goal.isGroupGoal", "SavingConsistency.periodIndex(",
            "transaction.date <= now", "priorTransactions.contains",
            "transaction.id", "transaction.amount > 0"
        ):
            self.assertIn(token, GATE, token)

    def test_only_post_commit_callback_can_arm_first_spark(self):
        start = DASH.index("private func confirmSaving()")
        end = DASH.index("private func openPendingDepositRequest()", start)
        fragment = DASH[start:end]
        self.assertLess(fragment.index("try modelContext.save()"),
                        fragment.index("let firstSparkEligible ="))
        self.assertLess(fragment.index("let firstSparkEligible ="),
                        fragment.index("completedSavingReward ="))
        self.assertIn("reward.firstSparkEligible", DASH)
        self.assertIn("firstSparkEligible: firstSparkEligible", ROOT_VIEW)
        self.assertIn("navigationManager.milestoneFirstSparkEligible", ROOT_VIEW)

    def test_account_reset_and_new_savings_clear_or_replace_trigger(self):
        self.assertIn("milestoneFirstSparkEligible = false", NAV)
        self.assertIn("milestoneFirstSparkEligible = firstSparkEligible", NAV)
        self.assertIn("navigationManager.resetAccountContext()", ROOT_VIEW)
        self.assertIn("navigationManager.milestoneFirstSparkEligible = false", ROOT_VIEW)
        self.assertIn("firstSparkEligible: false, // legacy navigation", ROOT_VIEW)
        self.assertIn("completedSavingReward = nil", DASH)

    def test_static_reduce_motion_and_finite_one_shot_timeline(self):
        self.assertIn("accessibilityReduceMotion", MOTION)
        self.assertIn("scenePhase == .active", MOTION)
        self.assertIn("guard !started else { return }", MOTION)
        self.assertIn("if reduceMotion", MOTION)
        self.assertIn("pipo.firstSpark.scene", MOTION)
        self.assertIn("Your first saving period is recorded.", MOTION)
        self.assertIn('Image("PipoV4Neutral")', MOTION)
        self.assertIn("Task.sleep(nanoseconds:", MOTION)
        # Sum of nonzero keyframe delay positions, not proof of real fps.
        delays = re.findall(r"\(\d, (\d[\d_]+),", MOTION)
        self.assertEqual(sum(int(x.replace("_", "")) for x in delays), 780_000_000)

    def test_native_regressions_are_authored_but_not_claimed_executed(self):
        for name in (
            "testFirstSparkOnlyAfterFirstOwnedScheduledContribution",
            "testFirstSparkRejectsCrossAccountFlexibleGroupInvalidAndFutureEntries",
            "testFirstSparkPresentationStateClearsOnAccountSwitch"
        ):
            self.assertIn("func " + name, TESTS)


if __name__ == "__main__":
    unittest.main()
