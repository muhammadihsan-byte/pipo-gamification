import Foundation
import XCTest
@testable import Pipo

final class GroupPlanJourneyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func draft() -> GroupPlanDraft {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        var draft = GroupPlanDraft(start: start, calendar: calendar)
        draft.title = "Japan trip"
        draft.category = .travel
        draft.groupName = "Sakura Squad"
        draft.targetText = "13.000.000"
        draft.usesDuration = true
        draft.months = 9
        draft.expected = "4"
        return draft
    }

    func testFigmaExampleCountsBothEndpointsAndUsesExpectedContributors() throws {
        var plan = draft()
        XCTAssertEqual(plan.schedule?.count, 10)
        XCTAssertEqual(plan.estimate, 325_000)
        try plan.prepareMember("@Ana")
        XCTAssertEqual(plan.estimate, 325_000)
        XCTAssertThrowsError(try plan.prepareMember(" ana "))
        XCTAssertThrowsError(try plan.prepareMember("@"))
        XCTAssertEqual(plan.preparedMembers, ["@Ana"])
        plan.expected = "4.5"
        XCTAssertFalse(plan.valid(.rules))
    }

    func testSingleTargetAndBreakdownRemainIndependentAcrossSwitches() {
        var plan = draft()
        plan.usesBreakdown = true
        XCTAssertNil(plan.target)
        plan.items = [.init(title: "Hotel", amount: "5.000.000"), .init(title: "Train", amount: "2.000.000")]
        XCTAssertEqual(plan.target, 7_000_000)
        plan.usesBreakdown = false
        XCTAssertEqual(plan.target, 13_000_000)
        plan.usesBreakdown = true
        plan.items[1].amount = ""
        XCTAssertNil(plan.target)
        plan.items[1].amount = "-3"
        XCTAssertFalse(plan.valid(.review))
        plan.items = []
        XCTAssertFalse(plan.valid(.target))
    }

    func testNoOverflowAndWholeRupiahRounding() {
        var plan = draft()
        plan.targetText = "101"
        XCTAssertEqual(plan.estimate, 3)
        plan.expected = String(Int.max)
        XCTAssertEqual(plan.estimate, 1)
        plan.usesBreakdown = true
        let large = String(1 << 62)
        plan.items = [.init(title: "A", amount: large), .init(title: "B", amount: large)]
        XCTAssertNil(plan.target)
    }

    func testFlexibleModeAllowsOptionalCheckInWithoutAFixedInstallment() {
        var plan = draft()
        plan.mode = .flexible
        XCTAssertTrue(plan.valid(.review))
        XCTAssertNil(plan.estimate)
        plan.checkIn = .weekly
        XCTAssertNil(plan.schedule)
        plan.mode = .equal
        XCTAssertEqual(plan.estimate, 325_000)
    }

    func testInvalidDatesAndCustomCategoryGateAdvancement() {
        var plan = draft()
        plan.category = .other
        plan.customCategory = " \n"
        var navigation = GroupPlanNavigation()
        navigation.advance(plan)
        XCTAssertEqual(navigation.step, .goal)
        plan.customCategory = " Tuition "
        navigation.advance(plan)
        XCTAssertEqual(navigation.step, .target)
        navigation.advance(plan)
        plan.usesDuration = false
        plan.selectedDate = plan.start
        navigation.advance(plan)
        XCTAssertEqual(navigation.step, .timeline)
        navigation.back(plan)
        XCTAssertEqual(navigation.step, .target)
        XCTAssertEqual(plan.categoryTitle, "Tuition")
        XCTAssertEqual(plan.target, 13_000_000)
    }

    func testReviewEditRevalidatesDependentStepsAndSuccessRequiresSaveEvent() {
        var plan = draft()
        var navigation = GroupPlanNavigation()
        for _ in 0..<6 { navigation.advance(plan) }
        XCTAssertEqual(navigation.step, .review)
        navigation.edit(.timeline)
        plan.usesDuration = false
        plan.selectedDate = calendar.date(byAdding: .day, value: 1, to: plan.start)!
        plan.monthDay = 30
        navigation.advance(plan)
        XCTAssertEqual(navigation.step, .rules)
        plan.mode = .flexible
        navigation.advance(plan)
        navigation.advance(plan)
        XCTAssertEqual(navigation.step, .review)
        navigation.didSave()
        navigation.back(plan)
        XCTAssertEqual(navigation.step, .success)
    }
}

import SwiftData
import SwiftUI
import UIKit

extension GroupPlanJourneyTests {
    @MainActor
    func testCaptureSavingPages() async throws {
        let schema = Schema([PersonalGoal.self, SubItem.self, UserProfile.self, SavingTransaction.self])
        let database = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let folder = URL.documentsDirectory.appendingPathComponent("SavingCaptures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func capture<V: View>(_ view: V, _ name: String) async throws {
            let host = UIHostingController(rootView: NavigationStack { view }
                .modelContainer(database).environment(SubscriptionManager())
                .environment(AuthStateManager(initialState: .authenticated)))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(700))
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
            let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"))
        }
        for step in PersonalPlanStep.allCases {
            try await capture(CreateGoalView(capture: step), "personal-\(step.rawValue)")
        }
        var plan = draft()
        plan.usesBreakdown = true
        plan.items = [.init(title: "Flights", amount: "6.000.000"), .init(title: "Hotel", amount: "5.000.000"),
                      .init(title: "Activities", amount: "2.000.000")]
        plan.goalDescription = "A trip with friends."
        plan.groupDescription = "Friends planning our Japan adventure, one step at a time."
        for step in GroupPlanStep.allCases {
            try await capture(CreateGroupPlanView(capture: step, plan: plan), "group-\(step.rawValue)")
        }
        plan.mode = .flexible
        try await capture(CreateGroupPlanView(capture: .rules, plan: plan), "group-flexible")
        window.isHidden = true
    }
}
