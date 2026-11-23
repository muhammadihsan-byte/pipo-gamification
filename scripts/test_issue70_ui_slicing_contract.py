#!/usr/bin/env python3
"""Linux-only static safety guard for the approved Spark period-history UI.

This guards key source and handoff invariants; it deliberately does NOT claim
native SwiftUI compilation, simulator rendering, or screenshot parity.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPARK = ROOT / "Pipo/Core/DesignSystem/PipoSparkV1.swift"
DETAIL = ROOT / "Pipo/Features/PersonalSaving/ReviewPlanView.swift"
NATIVE_TESTS = ROOT / "PipoTests/GamificationManagerTests.swift"


class Issue70OfflineSlicingTests(unittest.TestCase):
    def setUp(self):
        source = SPARK.read_text(encoding="utf-8")
        self.assertIn("// Issue #70 — read-only scheduled period history", source)
        self.slice = source.split(
            "// Issue #70 — read-only scheduled period history", 1
        )[1]
        self.goal_detail = DETAIL.read_text(encoding="utf-8")
        self.tests = NATIVE_TESTS.read_text(encoding="utf-8")

    def test_no_financial_or_profile_write_in_ui_slice(self):
        for unsafe in (
            "modelContext.save(", "modelContext.insert(", "modelContext.delete(",
            "profile.totalXP =", "goal.currentAmount =", "unlockedBadgeIds.append(",
            "SupabaseService(", "StoreKitManager(", ".transition(to:",
        ):
            self.assertNotIn(unsafe, self.slice, unsafe)

    def test_owner_scoped_and_invalid_rows_fail_closed(self):
        for contract in (
            "goal.ownerUserID == owner",
            "$0.userID == owner && $0.goalId == goal.id",
            "Set(relevant.map(\\.id)).count == relevant.count",
            "$0.amount.isFinite && $0.amount > 0",
            "$0.date <= now",
            "SavingConsistency.periodIndex(",
        ):
            self.assertIn(contract, self.slice, contract)

    def test_flexible_and_empty_goals_have_no_scheduled_pressure(self):
        self.assertIn("goal.rhythm != .flexible", self.slice)
        self.assertIn("guard !indices.isEmpty else { return [] }", self.slice)
        self.assertIn("index == current ? .open : .unrecorded", self.slice)
        self.assertIn("This period is still open", self.slice)
        self.assertIn("No saving recorded in this period", self.slice)
        self.assertNotIn('"Missed your saving"', self.slice)
        self.assertNotIn('"Streak failure"', self.slice)

    def test_responsive_rows_and_journal_action_remain_reachable(self):
        self.assertIn("VStack(alignment: .leading, spacing: 12)", self.slice)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", self.slice)
        self.assertIn(".frame(minHeight: 44", self.slice)
        self.assertIn(".accessibilityElement(children: .contain)", self.slice)
        self.assertIn('pipo.spark.history.openJournal', self.slice)
        self.assertNotIn(".frame(height:", self.slice)

        self.assertIn("PipoSparkPeriodHistoryView(", self.goal_detail)
        self.assertIn("transactions: ownedHistory(for: goal)", self.goal_detail)
        self.assertIn("userID: authStateManager.userID", self.goal_detail)
        self.assertIn("onOpenJournal: { showingSavingJournal = true }",
                      self.goal_detail)

    def test_xctests_cover_key_risks_but_remain_pending_native(self):
        for function in (
            "testIssue70PeriodHistoryOnlyUsesGoalOwnedScheduledWindows",
            "testIssue70CompassionateRecoveryAndNoFlexibleStreakCells",
            "testIssue70MonthlyWindowUsesCalendarMonthNotRollingThirtyDays",
        ):
            self.assertIn("func " + function + "()", self.tests)


if __name__ == "__main__":
    unittest.main()
