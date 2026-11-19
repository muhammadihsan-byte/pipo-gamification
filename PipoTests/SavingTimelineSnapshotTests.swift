import Foundation
import SwiftUI
import XCTest
@testable import Pipo

/// Native component snapshots for Figma visual QA; this is not an end-to-end UI navigation test.
@MainActor
final class SavingTimelineSnapshotTests: XCTestCase {
    func testPersonalAndGroupTimelineAtRegularAndNarrowWidths() {
        for isGroup in [false, true] {
            for width in [390.0, 320.0] {
                let height = width == 390.0 ? 852.0 : 760.0
                let view = SavingTimelineSnapshotFixture(isGroup: isGroup)
                    .frame(width: width, height: height)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(width: width, height: height)
                renderer.scale = 1

                let name = "\(isGroup ? "Group" : "Personal")-Timeline-\(Int(width))pt"
                guard let screenshot = renderer.uiImage else {
                    XCTFail("\(name) did not render")
                    continue
                }

                XCTAssertEqual(screenshot.size.width, width, accuracy: 1)
                XCTAssertEqual(screenshot.size.height, height, accuracy: 1)

                let attachment = XCTAttachment(image: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

@MainActor
private struct SavingTimelineSnapshotFixture: View {
    let isGroup: Bool
    private let calendar: Calendar
    private let start: Date
    @State private var entry: SavingDateEntry

    init(isGroup: Bool) {
        self.isGroup = isGroup
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let target = calendar.date(from: DateComponents(year: 2027, month: 7, day: 25))!
        self.start = start
        _entry = State(initialValue: SavingDateEntry(target, calendar: calendar))
    }

    var body: some View {
        SavingPlanPage(
            flowTitle: isGroup ? "Group saving plan" : "Personal saving plan",
            stepNumber: 3,
            count: isGroup ? 7 : 5,
            stepTitle: "Timeline",
            onBack: {}
        ) {
            if isGroup {
                GroupStepIntro(
                    "When do we want to reach our goal?",
                    "Choose a date to aim for, together."
                )
            } else {
                PersonalPlanIntro(
                    step: .timeline,
                    title: "When do you want to achieve it?",
                    subtitle: "Set a target for Buy new iPad."
                )
            }
            Text("Choose one · Required")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
            PersonalPlanChoice(title: "Target date", selected: true, action: {})
            SavingDateEditor(entry: $entry, start: start, calendar: calendar)
            PersonalPlanChoice(title: "Duration", selected: false, action: {})
            if isGroup {
                PersonalPlanNote(
                    title: "Plan starts · 25 October 2026",
                    message: "Aiming for 25 July 2027."
                )
            } else {
                Text("Aiming for 25 July 2027. Your date is an aspiration, not a promise — you can change it.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
            }
        } footer: {
            PersonalPlanActions(back: {}, title: "Continue", action: {})
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.accessibilityReduceMotion, true)
    }
}
