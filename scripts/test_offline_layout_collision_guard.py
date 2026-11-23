#!/usr/bin/env python3
"""Static bottom-edge collision prevention for core Pipo SwiftUI surfaces.

This guards source patterns only. It does NOT render SwiftUI and cannot certify
320pt/393pt screenshots, Dynamic Type, keyboard geometry or hit testing.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
def source(path):
    return (ROOT / path).read_text()

MANAGE = source("Pipo/Features/PersonalSaving/ManagePlanV2.swift")
DASH = source("Pipo/Features/Dashboard/ContentView.swift")
GOAL = source("Pipo/Features/PersonalSaving/ReviewPlanView.swift")
PLAN = source("Pipo/Features/PersonalSaving/PersonalPlanComponents.swift")
MILESTONE = source("Pipo/Features/Gamification/ConsistencyMilestoneView.swift")
UI_TEST = source("PipoUITests/PipoUIRecordingTests.swift")


class OfflineLayoutCollisionContract(unittest.TestCase):
    def test_manage_plan_footer_participates_in_scroll_safe_area(self):
        part = MANAGE.split("struct PipoManagePlanV2Sheet: View {", 1)[1]
        body = part.split("    private var topBar:", 1)[0]
        self.assertIn("GeometryReader { geometry in", body)
        self.assertIn("ScrollView {", body)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0) {", body)
        self.assertIn("footer(horizontal: horizontal)", body)
        self.assertNotIn("compactBottomReserve", body)
        self.assertNotIn(".frame(width: geometry.size.width", body)
        self.assertNotIn(".padding(.bottom, compactBottomReserve)", body)
        self.assertNotIn(".layoutPriority(1)", body)
        self.assertIn(".scrollDismissesKeyboard(.interactively)", body)

    def test_manage_plan_disclosures_scroll_not_cover_footer(self):
        body = MANAGE.split("struct PipoManagePlanV2Sheet: View {", 1)[1]
        self.assertEqual(body.count('Preview only · Changes are not saved'), 1)
        scroll_content = body.split("ScrollView {", 1)[1].split(".safeAreaInset(edge: .bottom", 1)[0]
        self.assertIn("Preview only · Changes are not saved", scroll_content)
        footer = body.split("private func footer(horizontal: CGFloat)", 1)[1]
        self.assertNotIn("Preview only · Changes are not saved", footer)
        self.assertIn(".accessibilityIdentifier(\"pipo.plan.v2.primary\")", footer)
        self.assertIn(".disabled(!actionAllowed)", footer)
        self.assertIn("case .review: return false", body)

    def test_achievements_collection_is_fully_scrollable(self):
        sheet = DASH.split("private var achievementsSheet: some View {", 1)[1].split(
            "private func groupGoalDetail(", 1
        )[0]
        self.assertIn("ScrollView {", sheet)
        self.assertIn("VStack(alignment: .leading, spacing: 20)", sheet)
        self.assertNotIn("LazyVStack(alignment: .leading, spacing: 20)", sheet)
        self.assertIn(".padding(.bottom, 56)", sheet)
        self.assertIn('pipo.achievements.nextMilestone', sheet)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", sheet)
        self.assertIn('Button("Done")', sheet)
        self.assertIn("earnedBadges", sheet)
        self.assertIn("lockedBadges", sheet)

    def test_other_sticky_surfaces_use_scroll_safe_area(self):
        for path, text in (
            ("PersonalPlanPage", PLAN),
            ("Flexible Plan Ready", GOAL),
            ("saving confirmation", DASH),
            ("milestone success", MILESTONE),
        ):
            with self.subTest(surface=path):
                self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", text)
        self.assertIn("ScrollView {", MILESTONE)
        self.assertIn("ScrollView {", GOAL)
        self.assertIn("ScrollView {", PLAN)

    def test_native_geometry_checks_are_authored_not_executed(self):
        self.assertIn("assertScrollableElementClearsBottomEdge(", UI_TEST)
        for label in (
            "Manage Plan target budget row",
            "Manage Plan date impact warning",
            "Achievements next milestone",
        ):
            self.assertIn(label, UI_TEST)
        self.assertIn("element.frame.maxY <= bottomBoundary - 10", UI_TEST)
        self.assertIn("element.frame.minY >= scroll.frame.minY + 8", UI_TEST)
        self.assertIn("scroll.swipeUp()", UI_TEST)
        self.assertIn("scroll.swipeDown()", UI_TEST)


if __name__ == "__main__":
    unittest.main()
