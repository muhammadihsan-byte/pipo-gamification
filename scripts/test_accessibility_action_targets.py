#!/usr/bin/env python3
"""Fail fast when SwiftUI accessibility grouping hides actionable child buttons.

Known native failure modes (Pipo #93/#95):
- An identifier on a compound card/stack may override descendant identifiers
  unless the container uses .accessibilityElement(children: .contain).
- Applying .accessibilityElement(children: .ignore/.combine) on an interactive
  row may expose a synthetic Other wrapper instead of its tappable Button.

Static scans are a supplement to real XCUI accessibility-tree testing, not a
proof of behavior on every iOS version or screen configuration.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Pipo"
CONTAINER = re.compile(
    r"(?:TicketCard|VStack|HStack|ZStack|LazyVStack|LazyHStack|ScrollView|"
    r"NavigationStack|Form|Section|Group|Grid)\s*(?:\([^{}]*\))?\s*$",
    re.DOTALL,
)
BUTTON = re.compile(r"\bButton\s*(?:\(|\{)")
IDENTIFIER = re.compile(r"\.accessibilityIdentifier\(\s*\"([^\"\n]+)")
GROUP = re.compile(
    r"\.accessibilityElement\(\s*children:\s*\.(ignore|combine|contain)\s*\)"
)


def strip_comments(text: str) -> str:
    """Ignore whole-line Swift comments (keeps line positions roughly stable)."""
    return "\n".join(
        "" if line.lstrip().startswith("//") else line
        for line in text.split("\n")
    )


def enclosing_view_block(text: str, position: int) -> tuple[str, str, str] | None:
    """Find the nearest completed SwiftUI closure preceding a modifier.

    This is an intentionally conservative scanner, not a Swift compiler AST;
    it checks cases with a clear last closure and a known container opener.
    """
    end = text.rfind("}", 0, position)
    if end < 0 or position - end > 350:
        return None
    depth = 1
    start = end - 1
    while start >= 0 and depth > 0:
        if text[start] == "}":
            depth += 1
        elif text[start] == "{":
            depth -= 1
        start -= 1
    if depth != 0:
        return None
    start += 1
    prefix = text[max(0, start - 220):start]
    body = text[start + 1:end]
    modifiers = text[end + 1:position]
    return prefix, body, modifiers


def unsafe_container_identifiers(path: Path) -> list[tuple[int, str]]:
    text = strip_comments(path.read_text(encoding="utf-8"))
    issues = []
    for match in IDENTIFIER.finditer(text):
        candidate = enclosing_view_block(text, match.start())
        if candidate is None:
            continue
        prefix, body, modifiers = candidate
        if not CONTAINER.search(prefix):
            continue
        if not BUTTON.search(body):
            continue
        if re.search(r"\.accessibilityElement\(\s*children:\s*\.contain\s*\)", modifiers):
            continue
        issues.append((text.count("\n", 0, match.start()) + 1, match.group(1)))
    return issues


def unsafe_grouped_actions(path: Path) -> list[tuple[int, str]]:
    text = strip_comments(path.read_text(encoding="utf-8"))
    issues = []
    for match in GROUP.finditer(text):
        if match.group(1) == "contain":
            continue
        candidate = enclosing_view_block(text, match.start())
        if candidate is None:
            continue
        prefix, body, _ = candidate
        # Static grouped cards containing an action should never suppress that
        # action's independent VoiceOver node.
        if CONTAINER.search(prefix) and BUTTON.search(body):
            issues.append((text.count("\n", 0, match.start()) + 1, match.group(1)))
    return issues


class AccessibilityActionTargetGuardTests(unittest.TestCase):
    def test_no_interactive_container_obscures_child_identifiers(self):
        failures = []
        for path in sorted(ROOT.rglob("*.swift")):
            failures += [
                f"{path.relative_to(ROOT)}:{line} container ID {name} owns a "
                "Button; use children: .contain or move ID onto a leaf"
                for line, name in unsafe_container_identifiers(path)
            ]
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_grouping_never_collapses_an_interactive_container(self):
        failures = []
        for path in sorted(ROOT.rglob("*.swift")):
            failures += [
                f"{path.relative_to(ROOT)}:{line} children: .{kind} hides "
                "a Button within a compound view"
                for line, kind in unsafe_grouped_actions(path)
            ]
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_journey_record_is_a_real_accessible_button(self):
        path = ROOT / "Core/DesignSystem/PipoApprovedCards.swift"
        text = strip_comments(path.read_text(encoding="utf-8"))
        start = text.index("private func entryRow(")
        end = text.index("private var badgeEntry", start)
        row = text[start:end]
        self.assertIn("Button {", row)
        self.assertIn('accessibilityIdentifier("pipo.journey.record.', row)
        self.assertIn('accessibilityHint("Opens the saved entry detail")', row)
        self.assertNotIn(".accessibilityElement(children: .ignore)", row)
        self.assertNotIn(".accessibilityElement(children: .combine)", row)

    def test_critical_existing_card_actions_are_not_parent_masked(self):
        paths = [
            ("Core/DesignSystem/PipoApprovedCards.swift",
             ("pipo.card.goalProgressB", "pipo.card.milestonesD",
              "pipo.card.completionB", "pipo.card.emptyStateB")),
            ("Core/DesignSystem/PipoTheme.swift", ("pipo.card.budgetBreakdownB",)),
            ("Features/Dashboard/ContentView.swift", ("pipo.dashboard.mascotReply",)),
        ]
        for relative, ids in paths:
            text = strip_comments((ROOT / relative).read_text(encoding="utf-8"))
            for identifier in ids:
                start = text.index(f'.accessibilityIdentifier("{identifier}")')
                context = enclosing_view_block(text, start)
                self.assertIsNotNone(context, relative + ": " + identifier)
                self.assertRegex(
                    context[2],
                    r"\.accessibilityElement\(\s*children:\s*\.contain\s*\)",
                    relative + ": " + identifier + " must retain child actions",
                )


if __name__ == "__main__":
    unittest.main()
