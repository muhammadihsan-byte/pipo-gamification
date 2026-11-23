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
CARDS = source("Pipo/Core/DesignSystem/PipoApprovedCards.swift")
GOAL = source("Pipo/Features/PersonalSaving/ReviewPlanView.swift")
PLAN = source("Pipo/Features/PersonalSaving/PersonalPlanComponents.swift")
MILESTONE = source("Pipo/Features/Gamification/ConsistencyMilestoneView.swift")
UI_TEST = source("PipoUITests/PipoUIRecordingTests.swift")
IOS_CI = source(".github/workflows/ios-build.yml")


class OfflineLayoutCollisionContract(unittest.TestCase):
    def test_accessibility_typography_adapts_without_clipping_or_hiding_values(self):
        self.assertIn("private func progressSummary(axis: Axis)", MANAGE)
        self.assertIn("ViewThatFits(in: .horizontal)", MANAGE)
        self.assertIn("private func monthCountSummary", CARDS)
        self.assertIn("AnyLayout(VStackLayout(alignment: .leading, spacing: 8))", CARDS)
        self.assertIn("AnyLayout(HStackLayout(spacing: 8))", CARDS)
        self.assertIn("if dynamicTypeSize.isAccessibilitySize {", CARDS)
        self.assertIn("multilineTextAlignment(.center)", DASH)

    def test_one_shot_native_visual_qa_gate_is_retired_before_merge(self):
        self.assertIn("id: visual_layout", IOS_CI)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && inputs.validation_mode == 'visual-layout-qa'",
            IOS_CI
        )
        self.assertNotIn("github.head_ref == 'fix/pipo-ax-typography-qa-20261124'", IOS_CI)

    def test_ax3_manage_plan_preserves_semantics_with_compact_typography(self):
        self.assertIn("if step == .overview && dynamicTypeSize.isAccessibilitySize", MANAGE)
        self.assertIn('.accessibilityLabel("Goal: " + original.title)', MANAGE)
        self.assertIn('Text("What do you want to adjust?")', MANAGE)
        self.assertIn("? .title3.bold() : .title2.bold()", MANAGE)
        self.assertIn('Text(dynamicTypeSize.isAccessibilitySize && value == "ALREADY RECORDED"', MANAGE)
        self.assertIn('Text(step == .overview && dynamicTypeSize.isAccessibilitySize', MANAGE)
        self.assertIn('? "Choose an edit" : actionLabel)', MANAGE)
        self.assertIn(".accessibilityLabel(actionLabel)", MANAGE)
        self.assertIn(".lineLimit(step == .overview ? 1 : nil)", MANAGE)

    def test_group_and_personal_primary_ctas_share_approved_pink(self):
        # Approved GROUP/03 Figma CTA uses bright #FF6584 plus raised edge.
        # White text on that surface would be below 4.5:1, so use ink.
        self.assertIn("shape.fill(PersonalPlanStyle.pink.opacity(", PLAN)
        self.assertIn(
            ".foregroundStyle(dimmed ? PersonalPlanStyle.muted : PersonalPlanStyle.ink)",
            PLAN
        )
        self.assertIn("shape.fill(PersonalPlanStyle.berry)", PLAN)
        self.assertNotIn("PersonalPlanStyle.buttonEdge.opacity(", PLAN)

    def test_manage_plan_footer_is_bounded_by_compact_viewport(self):
        part = MANAGE.split("struct PipoManagePlanV2Sheet: View {", 1)[1]
        body = part.split("    private var topBar:", 1)[0]
        self.assertIn("GeometryReader { geometry in", body)
        self.assertIn("ScrollView {", body)
        self.assertIn("footer(horizontal: horizontal)", body)
        self.assertIn(".frame(width: geometry.size.width,", body)
        self.assertIn("let hostHeight = max(0, geometry.size.height - geometry.safeAreaInsets.top)", body)
        self.assertIn("height: hostHeight, alignment: .top)", body)
        self.assertNotIn("height: geometry.size.height, alignment: .top)", body)
        self.assertEqual(body.count("height: hostHeight, alignment: .top)"), 1,
                         "Only the outer NavigationStack may own the inset-corrected host height")
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)", body)
        self.assertIn("footer(horizontal: horizontal)\n                        .padding(.bottom, 12)", body)
        self.assertNotIn("compactBottomReserve", body)
        self.assertNotIn(".safeAreaInset(edge: .bottom, spacing: 0)", body)
        self.assertNotIn(".padding(.bottom, compactBottomReserve)", body)
        self.assertNotIn(".layoutPriority(1)", body)
        self.assertIn(".scrollDismissesKeyboard(.interactively)", body)

    def test_manage_plan_disclosures_scroll_not_cover_footer(self):
        body = MANAGE.split("struct PipoManagePlanV2Sheet: View {", 1)[1]
        self.assertEqual(body.count('Preview only · Changes are not saved'), 1)
        scroll_content = body.split("ScrollView {", 1)[1].split(".scrollDismissesKeyboard(.interactively)", 1)[0]
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


    def test_native_visual_batch_requires_manual_dispatch_not_labels(self):
        self.assertIn("          - visual-layout-qa", IOS_CI)
        self.assertIn("id: visual_layout", IOS_CI)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && inputs.validation_mode == 'visual-layout-qa'",
            IOS_CI
        )
        # PR #101's temporary label override is gone. Other retained
        # steps may mention labels without being able to start a runner.
        self.assertNotIn("github.event.action == 'labeled'", IOS_CI)
        self.assertNotIn("github.event.pull_request.number == 101", IOS_CI)
        self.assertNotIn("EXACT_NATIVE_QA_HEAD=$EXPECTED_SHA", IOS_CI)
        header = IOS_CI.split("  workflow_dispatch:", 1)[0]
        self.assertNotIn("      - labeled", header)
        job_gate = IOS_CI.split("  build-and-test:", 1)[1].split("    runs-on: macos-15", 1)[0]
        self.assertIn("(github.event_name == 'pull_request' && github.event.pull_request.draft == false)", job_gate)
        self.assertNotIn("github.event.label", job_gate)
        legacy_gate = IOS_CI.split("  issue80-integrated-qa:", 1)[1].split("    runs-on: macos-15", 1)[0]
        self.assertIn("false # Owner-paused:", legacy_gate)
        legacy_bridge_gate = IOS_CI.split("  issue80-legacy-bridge-native:", 1)[1].split("    runs-on: macos-15", 1)[0]
        self.assertIn("false # Owner-paused:", legacy_bridge_gate)
        # The focused native suite is ready to run later, NOT executed by
        # this Linux static assertion or Draft PR CI.
        for method in (
            "testJourneyWaveAEmptyStatesAndRealHistory",
            "testManagePlanV2TargetAndDateEditorsAreFocusedAndNonMutating",
            "testManagePlanV2OverviewFlexibleImpactReviewAndMoneyOutSafety",
            "testAllElevenApprovedCardFamilies",
            "testGlobalV1AccessibilityLabelsAndTargetsAtLargeText",
        ):
            self.assertIn("-only-testing:PipoUITests/PipoUIRecordingTests/" + method, IOS_CI)


if __name__ == "__main__":
    unittest.main()
