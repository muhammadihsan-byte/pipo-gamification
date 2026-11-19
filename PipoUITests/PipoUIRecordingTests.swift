import XCTest

/// Drives real SwiftUI screens inside the iOS Simulator while simctl records MP4s.
/// The app uses a Debug-only in-memory model container and a fake signed-in state.
/// No credentials, payment transactions, or actual invitations are used.
@MainActor
final class PipoUIRecordingTests: XCTestCase {
    private let app = XCUIApplication()

    func testPersonalSavingJourney() {
        launchFromDashboard()
        tapButton("Create a saving goal")
        tapButton("Personal saving")

        XCTAssertTrue(app.staticTexts["What are you saving for?"].waitForExistence(timeout: 20))
        typeText("Goal name", value: "Pipo QA Personal Trip")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["How much do you need?"].waitForExistence(timeout: 15))
        typeText("Target amount in rupiah", value: "5000000")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["When do you want to achieve it?"].waitForExistence(timeout: 15))
        interactWithCalendar()
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["What’s your saving rhythm?"].waitForExistence(timeout: 15))
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["Review your saving plan"].waitForExistence(timeout: 20))
        tapButton("Start saving plan")
        tapButton("Done")
        XCTAssertTrue(app.staticTexts["Pipo QA Personal Trip"].waitForExistence(timeout: 20))
    }

    func testGroupSavingJourney() {
        launchFromDashboard()
        tapButton("Create a saving goal")
        tapButton("Group saving")

        XCTAssertTrue(app.staticTexts["What are you saving for?"].waitForExistence(timeout: 20))
        typeText("Goal name", value: "Pipo QA Group Trip")
        // The category field is below the keyboard on compact iPhones.
        // Scroll the actual form first, letting the interactive keyboard dismiss.
        let form = app.scrollViews.firstMatch
        if form.exists { form.swipeUp() }
        tapButton("Goal category")
        tapButton("Travel")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["How much do we need together?"].waitForExistence(timeout: 15))
        typeText("Shared target in rupiah", value: "9000000")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["When do we want to reach our goal?"].waitForExistence(timeout: 15))
        interactWithCalendar()
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["How do we want to contribute?"].waitForExistence(timeout: 15))
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["Let’s set up our group."].waitForExistence(timeout: 15))
        typeText("Group name", value: "Pipo QA Team")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["Who’s joining your saving journey?"].waitForExistence(timeout: 15))
        tapButton("Invite later")

        XCTAssertTrue(app.staticTexts["Your group saving plan"].waitForExistence(timeout: 20))
        tapButton("Create Group Saving")
        XCTAssertTrue(app.staticTexts["Your saving team is ready!"].waitForExistence(timeout: 20))
        tapButton("Open dashboard")
        XCTAssertTrue(app.buttons["Create a saving goal"].waitForExistence(timeout: 20))
    }

    private func launchFromDashboard() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-visual-qa"]
        app.launch()
        XCTAssertTrue(app.buttons["Create a saving goal"].waitForExistence(timeout: 30),
                      "The Debug-only Dashboard did not launch")
    }

    private func typeText(_ label: String, value: String) {
        let field = app.textFields[label].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Missing field: \(label)")
        bringIntoView(field)
        field.tap()
        field.typeText(value)
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing button: \(label)")
        bringIntoView(button)
        XCTAssertTrue(button.isEnabled, "Disabled button: \(label)")
        button.tap()
    }

    private func interactWithCalendar() {
        tapButton("Next month")
        let day = app.buttons["pipo.qa.calendar.day.15"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 12), "Inline calendar day 15 is missing")
        bringIntoView(day)
        if !day.isHittable {
            let strip = app.scrollViews["pipo.qa.calendar.horizontal"].firstMatch
            if strip.exists {
                strip.swipeLeft()
                if !day.isHittable { strip.swipeRight() }
            }
        }
        XCTAssertTrue(day.isHittable, "Day 15 must be reachable on a narrow iPhone")
        day.tap()
    }

    private func bringIntoView(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "UI element is not reachable: \(element.identifier)")
    }
}
