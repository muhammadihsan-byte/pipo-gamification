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
        // Close the keyboard, then expand the real category selector.
        // On compact iPhones the choices initially sit below the visible scroll area.
        let keyboardReturn = app.keyboards.buttons["return"].firstMatch
        if keyboardReturn.exists { keyboardReturn.tap() }
        let form = app.scrollViews.firstMatch
        if form.exists { form.swipeUp() }
        tapButton("Goal category")
        if form.exists { form.swipeUp() }
        tapButton("pipo.qa.group.category.Travel")
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

    /// Post-login onboarding: V4 wave, nickname, motivation, optional
    /// widget walkthrough and returning-user account-scoped behavior.
    /// Uses a fixed Debug-only account and never signs in to a real backend.
    func testPostLoginPersonalizationAndWidgetPreview() {
        continueAfterFailure = false

        launchOnboarding()
        XCTAssertTrue(app.staticTexts["Little steps. Big dreams."].waitForExistence(timeout: 30))
        attachOnboardingScreen("01 - V4 companion and connected greeting bubble")
        let pipo = app.buttons["pipo.greet"].firstMatch
        XCTAssertTrue(pipo.waitForExistence(timeout: 15), "V4 wave interaction is unavailable")
        XCTAssertTrue(pipo.isEnabled)
        let referenceMascotHeight = pipo.frame.height
        XCTAssertGreaterThan(referenceMascotHeight, 100, "V4 mascot must be visible at usable size")
        pipo.tap()

        tapButton("pipo.onboarding.continue")
        XCTAssertTrue(app.staticTexts["What should I call you?"].waitForExistence(timeout: 12))
        XCTAssertLessThan(abs(app.buttons["pipo.greet"].firstMatch.frame.height - referenceMascotHeight), 2)
        attachOnboardingScreen("02 - Consistent V4 size and nickname bubble")
        typeText("pipo.onboarding.nickname", value: "Alex")
        let done = app.keyboards.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        tapButton("pipo.onboarding.continue")

        XCTAssertTrue(app.staticTexts["What brings you to Pipo?"].waitForExistence(timeout: 12))
        tapButton("pipo.onboarding.back")
        XCTAssertTrue(app.staticTexts["What should I call you?"].waitForExistence(timeout: 12))
        tapButton("pipo.onboarding.continue")
        tapButton("pipo.onboarding.motivation.excitingGoal")
        // The contextual reply is a visual transition inside the conversation
        // bubble. Review its retained screenshot; the accessibility tree may
        // aggregate the bubble contents into one element on iOS.
        XCTAssertLessThan(abs(app.buttons["pipo.greet"].firstMatch.frame.height - referenceMascotHeight), 2)
        attachOnboardingScreen("03 - Mascot response inside connected bubble")
        tapButton("pipo.onboarding.continue")
        XCTAssertTrue(app.staticTexts["Want Pipo on your Home Screen?"].waitForExistence(timeout: 12))
        XCTAssertLessThan(abs(app.buttons["pipo.greet"].firstMatch.frame.height - referenceMascotHeight), 2)
        attachOnboardingScreen("04 - Consistent V4 size on widget page")

        tapButton("pipo.onboarding.continue")
        XCTAssertTrue(app.staticTexts["Add Pipo to your Home Screen"].waitForExistence(timeout: 12))
        attachOnboardingScreen("Optional widget setup instructions")
        tapButton("pipo.onboarding.widget.done")

        XCTAssertTrue(app.staticTexts["Hey, Alex!"].waitForExistence(timeout: 25),
                      "Home must use saved onboarding nickname")
        XCTAssertTrue(app.buttons["Create a saving goal"].waitForExistence(timeout: 15))
        attachOnboardingScreen("Personalized Pipo Home")

        // Relaunch as the SAME authenticated user without the forced-first-run
        // flag. Account-specific completion should bypass onboarding entirely.
        app.terminate()
        app.launchArguments = ["-pipo-onboarding-qa-returning"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hey, Alex!"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Little steps. Big dreams."].exists,
                       "A returning account must not repeat onboarding")

        // Also cover both optional Skip actions in the same controlled run.
        app.terminate()
        launchOnboarding()
        tapButton("pipo.onboarding.continue")
        tapButton("pipo.onboarding.skip")
        XCTAssertTrue(app.staticTexts["What brings you to Pipo?"].waitForExistence(timeout: 12))
        tapButton("pipo.onboarding.skip")
        XCTAssertTrue(app.staticTexts["Want Pipo on your Home Screen?"].waitForExistence(timeout: 12))
        tapButton("pipo.onboarding.widget.skip")
        XCTAssertTrue(app.buttons["Create a saving goal"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["Pipo"].waitForExistence(timeout: 12),
                      "Skipped personalization should leave the default Home greeting")
        attachOnboardingScreen("Skipped options lead directly to Home")
    }

    private func launchOnboarding() {
        app.launchArguments = ["-pipo-onboarding-qa"]
        app.launch()
    }

    private func attachOnboardingScreen(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
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
