import XCTest

final class SavingFlowUITests: XCTestCase {
    @MainActor
    func testCreatePersonalAndGroupFromDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SavingJourneyUITest"]
        app.launch()
        app.buttons["Create a saving goal"].tap()
        app.buttons["Personal saving"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        fill("Goal name", "Studio monitor", in: app)
        advance(app)
        fill("Target amount in rupiah", "7500000", in: app)
        advance(app)
        advance(app)
        advance(app)
        let start = app.buttons["Start saving plan"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        snapshot(app, "personal-saved")
        done.tap()
        app.buttons["Saving goals"].tap()

        app.buttons["Create a saving goal"].tap()
        app.buttons["Group saving"].tap()
        fill("Goal name", "Japan trip", in: app)
        tap(app.buttons["Goal category"], in: app)
        tap(app.buttons["Travel"], in: app)
        advance(app)
        fill("Shared target in rupiah", "13000000", in: app)
        advance(app)
        advance(app)
        advance(app)
        fill("Group name", "Sakura Squad", in: app)
        advance(app)
        app.buttons["Invite later"].tap()
        XCTAssertTrue(app.buttons["Create Group Saving"].waitForExistence(timeout: 10))
        app.buttons["Create Group Saving"].tap()
        let dashboard = app.buttons["Open dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        snapshot(app, "group-saved")
        dashboard.tap()
        XCTAssertTrue(app.staticTexts["Japan trip"].waitForExistence(timeout: 8))
    }

    @MainActor private func advance(_ app: XCUIApplication) {
        let button = app.buttons["Continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }

    @MainActor private func fill(_ label: String, _ value: String, in app: XCUIApplication) {
        let field = app.textFields[label]
        tap(field, in: app)
        field.typeText(value)
    }

    @MainActor private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Could not reach \(element)")
        element.tap()
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
