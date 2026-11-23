"""Flexible Saving V2 source-only UI contract (no macOS or native rendering).

The approved seven-screen Figma handoff is not a bank transfer flow.
This guard catches regressions in copy, routing and layout boundaries while
XCTest/screenshot/VoiceOver remain pending on the paused Mac runner.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CREATE = (ROOT / "Pipo/Features/PersonalSaving/CreateGoalView.swift").read_text()
REVIEW = (ROOT / "Pipo/Features/PersonalSaving/ReviewPlanView.swift").read_text()
DASH = (ROOT / "Pipo/Features/Dashboard/ContentView.swift").read_text()
ROOTVIEW = (ROOT / "Pipo/App/RootView.swift").read_text()
PLANPAGE = (ROOT / "Pipo/Features/PersonalSaving/PersonalPlanComponents.swift").read_text()
TESTS = (ROOT / "PipoTests/PersonalGoalTests.swift").read_text()


class FlexibleV2OfflineContract(unittest.TestCase):
    def test_choice_is_full_width_with_no_streak_pressure(self):
        self.assertIn('ForEach(SavingRhythm.allCases) { option in', CREATE)
        self.assertIn('No saving days to miss.', CREATE)
        self.assertIn('Whenever you can. No saving streak.', CREATE)
        self.assertIn('title: "Flexible is a valid rhythm."', CREATE)
        self.assertIn('pipo.flex.v2.rhythm.', CREATE)
        self.assertNotIn('HStack(spacing: 8) {\n                    rhythmChoice(.daily)', CREATE)
        self.assertIn("if rhythm == .flexible {", CREATE)

    def test_review_separates_goal_target_from_saving_dates(self):
        self.assertIn("private var flexibleReview: some View", REVIEW)
        self.assertIn('flexibleReviewRow("Goal timeline"', REVIEW)
        self.assertIn('flexibleReviewRow("Saving dates", value: "Not scheduled")', REVIEW)
        self.assertIn("The goal timeline above is separate from your saving rhythm.", REVIEW)
        self.assertIn("No money is moved or automatically deposited.", REVIEW)
        self.assertIn("plan.rhythm == .flexible", REVIEW)

    def test_ready_actions_go_to_existing_manual_flow_without_deposit(self):
        self.assertIn('Button("Record first saving") { onRecordFirst(goalID) }', REVIEW)
        self.assertIn('Button("Not now, view my goal") { onCreated(goalID) }', REVIEW)
        self.assertIn("onRecordFirst: onRecordFirst", CREATE)
        self.assertIn("onRecordFirst: { goalID in", ROOTVIEW)
        self.assertIn("navigationManager.requestDeposit(goalID: goalID)", ROOTVIEW)
        self.assertIn("try modelContext.save()", REVIEW)
        self.assertIn("createdGoalID = goal.id", REVIEW)

    def test_flexible_goal_renders_true_fractional_progress_and_no_deadline_card(self):
        self.assertIn("fractionLength(0...2)", REVIEW)
        self.assertIn('pipo.flex.v2.goalPace', REVIEW)
        self.assertIn("No saving days to miss.", REVIEW)
        self.assertIn("ownedHistory(for: goal)", REVIEW)
        self.assertIn("AccountScope.owns(goal, userID: authStateManager.userID)", REVIEW)
        self.assertIn("PipoActivityHistoryDCard", REVIEW)

    def test_native_sheet_and_footer_have_scroll_safe_separation(self):
        self.assertIn("private var saveConfirmation: some View", DASH)
        self.assertIn('pipo.flex.v2.manualPace', DASH)
        self.assertIn("try modelContext.save()", DASH)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", DASH)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", PLANPAGE)
        self.assertIn("private func flexiblePlanReady(goalID: UUID)", REVIEW)
        self.assertIn("ScrollView {", REVIEW)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", REVIEW)
        self.assertIn('PipoV4Joy', REVIEW)

    def test_native_regression_source_authored_but_not_executed(self):
        self.assertIn('testFlexibleV2ReturningGoalPreservesFractionalManualProgress', TESTS)
        self.assertIn('testFlexibleV2OneManualContributionReachesQuarterWithoutStreak', TESTS)
        self.assertIn('XCTAssertEqual(profile.streakDays, 0', TESTS)


if __name__ == "__main__":
    unittest.main()
