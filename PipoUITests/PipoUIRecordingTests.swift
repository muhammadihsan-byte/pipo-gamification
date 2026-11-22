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
        typeText("pipo.goal.currency.amount", value: "5000000")
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["When do you want to achieve it?"].waitForExistence(timeout: 15))
        interactWithCalendar()
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["What’s your saving rhythm?"].waitForExistence(timeout: 15))
        tapButton("Continue")

        XCTAssertTrue(app.staticTexts["Review your saving plan"].waitForExistence(timeout: 20))
        tapButton("Start saving plan")
        tapButton("View my goal")
        XCTAssertTrue(app.staticTexts["Pipo QA Personal Trip"].waitForExistence(timeout: 20))
    }

    /// Global V1 Option B: currency selection belongs to Create Goal and
    /// clears any amount entered under a different code. No network or live user.
    func testGlobalExperienceUSDGoalCurrencySelectionAndReopen() {
        // A synthetic account in a separate on-disk simulator-only store,
        // not the real user's SwiftData or Supabase environment.
        app.launchArguments = ["-pipo-global-currency-qa", "-pipo-global-currency-qa-reset"]
        app.launch()
        tapButton("Create a saving goal")
        tapButton("Personal saving")
        typeText("Goal name", value: "New Laptop USD")
        tapButton("Continue")
        XCTAssertTrue(app.staticTexts["How much do you need?"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pipo.goal.currency.choose"].exists)
        attachOnboardingScreen("Global V1 — Currency confirmed at target step")
        // Begin with an explicit IDR choice independent of simulator region.
        tapButton("pipo.goal.currency.choose")
        let idrSearch = app.searchFields.firstMatch
        XCTAssertTrue(idrSearch.waitForExistence(timeout: 15))
        idrSearch.tap()
        idrSearch.typeText("IDR")
        tapButton("pipo.goal.currency.IDR")
        typeText("pipo.goal.currency.amount", value: "6000000")
        tapButton("pipo.goal.currency.choose")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), "Searchable currency sheet must appear")
        search.tap()
        search.typeText("USD")
        tapButton("pipo.goal.currency.USD")
        let target = app.textFields["pipo.goal.currency.amount"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        XCTAssertTrue((target.value as? String ?? "").isEmpty,
                      "Old IDR amount must be cleared on USD selection")
        XCTAssertFalse(app.buttons["Continue"].isEnabled,
                       "Cannot continue until a fresh USD amount is entered")
        attachOnboardingScreen("Global V1 — ISO selection resets ambiguous amount")
        typeText("pipo.goal.currency.amount", value: "1500.50")
        tapButton("Continue")
        interactWithCalendar()
        tapButton("Continue")
        tapButton("Continue")
        XCTAssertTrue(app.staticTexts["Review your saving plan"].waitForExistence(timeout: 15))
        attachOnboardingScreen("Global V1 — USD review before local creation")
        tapButton("Start saving plan")
        tapButton("View my goal")
        XCTAssertTrue(app.staticTexts["New Laptop USD"].waitForExistence(timeout: 20))
        attachOnboardingScreen("Global V1 — Goal Detail USD after local save")
        XCTAssertTrue(app.buttons["pipo.goal.recordSaving"].exists)
        tapButton("pipo.goal.recordSaving")
        XCTAssertTrue(app.textFields["Amount in USD"].waitForExistence(timeout: 15))
        typeText("Amount in USD", value: "0.01")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        attachOnboardingScreen("Global V1 — Manual USD saving is not a bank transfer")
        tapButton("Save")

        // Terminate and start an actual new app process against the same
        // synthetic disk store. We must not call this a relaunch test without
        // exercising a real restart.
        app.terminate()
        app.launchArguments = ["-pipo-global-currency-qa"]
        app.launch()
        let persistedGoal = app.staticTexts["New Laptop USD"].firstMatch
        XCTAssertTrue(persistedGoal.waitForExistence(timeout: 20),
                      "Stored USD goal must survive app relaunch")
        XCTAssertFalse(app.staticTexts["Amount unavailable"].exists,
                       "USD scheduled saving amount must render from exact minor units")
        persistedGoal.tap()
        XCTAssertTrue(app.buttons["pipo.goal.recordSaving"].waitForExistence(timeout: 15))
        attachOnboardingScreen("Global V1 — USD goal survives actual app restart")
        // Non-IDR Money Out is an inline explanation, never an unsupported
        // sheet with accidental IDR amount entry.
        let moneyOutUnavailable = app.descendants(matching: .any)
            .matching(identifier: "pipo.currency.moneyOut.unavailable").firstMatch
        XCTAssertTrue(moneyOutUnavailable.waitForExistence(timeout: 15),
            "Goal Detail must explain that Money Out isn't available for USD")
        XCTAssertFalse(app.buttons["pipo.goal.moneyOutPreview"].exists,
            "No unsupported Money Out sheet should be enterable for USD")
        XCTAssertFalse(app.textFields["pipo.card.moneyOut.amount"].exists)
        attachOnboardingScreen("Global V1 — Non-IDR Money Out safely unavailable")
        XCTAssertTrue(app.buttons["pipo.goal.planRevisionPreview"].waitForExistence(timeout: 15))
        // Never let the pinned Record Saving CTA intercept an offscreen tap.
        tapButtonAboveSavingFooter("pipo.goal.planRevisionPreview")
        attachOnboardingScreen("Global V1 — Manage Plan presentation after USD restart")
        XCTAssertFalse(app.navigationBars["Record a saving"].exists,
                       "Manage Plan tap must not open Record Saving")
        XCTAssertTrue(app.staticTexts["pipo.plan.v2.title"].waitForExistence(timeout: 15),
                      "Manage Plan modal was not presented after USD restart: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].waitForExistence(timeout: 15))
        tapButton("pipo.plan.v2.editTarget")
        XCTAssertTrue(app.staticTexts["TARGET AMOUNT · USD"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["pipo.plan.v2.primary"].isEnabled)
        attachOnboardingScreen("Global V1 — Manage Plan V2 goal-level currency")
    }


    /// Issue #40: runs against an isolated, disk-backed synthetic account.
    /// A DEBUG-only failed local persistence must preserve the typed amount,
    /// leave XP/badges unchanged and allow a real first-saving retry.
    func testIssue40FirstSaveActivationSurvivesFailureAndRelaunch() {
        continueAfterFailure = false
        app.launchArguments = [
            "-pipo-global-currency-qa", "-pipo-global-currency-qa-reset",
            "-pipo-first-save-force-persist-error"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Your first saving goal"].waitForExistence(timeout: 20))
        // Transparency copy sits below the folded Home viewport on compact
        // devices; capture the scroll instead of asserting an offscreen AX row.
        attachOnboardingScreen("Issue 40 — no goals, manual money disclosure")
        tapButton("Create a saving goal")
        tapButton("Personal saving")
        typeText("Goal name", value: "First Step QA")
        tapButton("Continue")

        // The real existing five-step creation flow is preserved.
        XCTAssertTrue(app.staticTexts["How much do you need?"].waitForExistence(timeout: 15))
        tapButton("pipo.goal.currency.choose")
        let currencySearch = app.searchFields.firstMatch
        XCTAssertTrue(currencySearch.waitForExistence(timeout: 15))
        currencySearch.tap()
        currencySearch.typeText("IDR")
        tapButton("pipo.goal.currency.IDR")
        typeText("pipo.goal.currency.amount", value: "6000000")
        tapButton("Continue")
        interactWithCalendar()
        tapButton("Continue")
        tapButton("Continue")
        XCTAssertTrue(app.staticTexts["Review your saving plan"].waitForExistence(timeout: 15))
        tapButton("Start saving plan")
        XCTAssertTrue(app.staticTexts["Well, look at that."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["First Step unlocked"].exists,
                       "Creating a plan is not recording a contribution")
        attachOnboardingScreen("Issue 40 — plan ready with no earned rewards")
        tapButton("pipo.firstSave.later")

        let record = app.buttons["pipo.dashboard.recordSaving"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 20))
        XCTAssertEqual(record.label, "Record my first save")
        attachOnboardingScreen("Issue 40 — new zero-progress focus goal and no-pressure choice")

        tapButton("pipo.dashboard.recordSaving")
        let amount = app.textFields["Amount in IDR"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Empty amount cannot be saved")
        typeText("Amount in IDR", value: "75000")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        attachOnboardingScreen("Issue 40 — manually recorded amount, no auto-fill")
        tapButton("Save")

        XCTAssertTrue(app.staticTexts["pipo.firstSave.saveError"].waitForExistence(timeout: 12),
                      "A local write failure must remain on the entry sheet")
        XCTAssertEqual(amount.value as? String, "75000",
                       "An unsuccessful write must preserve the amount for retry")
        XCTAssertFalse(app.staticTexts["First Step unlocked"].exists,
                       "XP and badges are never awarded for a failed save")
        attachOnboardingScreen("Issue 40 — failed local write keeps entered money")
        tapButton("Cancel")

        // The new goal is already durably saved; failed contribution is not.
        app.terminate()
        app.launchArguments = ["-pipo-global-currency-qa"]
        app.launch()
        XCTAssertTrue(record.waitForExistence(timeout: 20))
        XCTAssertEqual(record.label, "Record my first save",
                       "No phantom saving after force-quit and relaunch")

        tapButton("pipo.dashboard.recordSaving")
        typeText("Amount in IDR", value: "75000")
        tapButton("Save")
        XCTAssertTrue(app.staticTexts["pipo.firstSave.badge"].waitForExistence(timeout: 20),
                      "First Step badge must appear after persisted first saving")
        XCTAssertTrue(app.staticTexts["pipo.firstSave.bubble"].exists)
        XCTAssertTrue(app.staticTexts["+300 XP"].exists)
        attachOnboardingScreen("Issue 40 — persisted first saving earns First Step and XP")

        app.terminate()
        app.launchArguments = ["-pipo-global-currency-qa"]
        app.launch()
        XCTAssertTrue(record.waitForExistence(timeout: 20))
        XCTAssertEqual(record.label, "Record a saving",
                       "Return visit cannot offer or replay the first-saving reward")
        XCTAssertFalse(app.staticTexts["First Step unlocked"].exists)
        attachOnboardingScreen("Issue 40 — recorded progress survives restart without celebration")
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
        assertMascotSettlesToSize(referenceMascotHeight)
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
        assertMascotSettlesToSize(referenceMascotHeight)
        attachOnboardingScreen("03 - Mascot response inside connected bubble")
        tapButton("pipo.onboarding.continue")
        XCTAssertTrue(app.staticTexts["Want Pipo on your Home Screen?"].waitForExistence(timeout: 12))
        assertMascotSettlesToSize(referenceMascotHeight)
        attachOnboardingScreen("04 - Consistent V4 size on widget page")

        tapButton("pipo.onboarding.continue")
        XCTAssertTrue(app.staticTexts["Add Pipo to your Home Screen"].waitForExistence(timeout: 12))
        attachOnboardingScreen("Optional widget setup instructions")
        tapButton("pipo.onboarding.widget.done")

        XCTAssertTrue(app.staticTexts["Hey, Alex!"].waitForExistence(timeout: 25),
                      "Home must use saved onboarding nickname")
        XCTAssertTrue(app.staticTexts["Your first saving goal"].waitForExistence(timeout: 15),
                      "First-time Home should explain the first saving goal")
        XCTAssertTrue(app.staticTexts["Big idea? Give it a place to grow."].exists,
                      "Home should reflect the selected onboarding motivation")
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
        XCTAssertTrue(app.staticTexts["Whatever you're planning, start when you're ready."].exists,
                      "Skipped personalization should have a friendly default first-goal message")
        attachOnboardingScreen("Skipped options lead directly to Home")
    }


    /// Dashboard B visual contract using only seeded in-memory simulator data.
    /// The PR workflow records this in one controlled native iOS run.
    func testReturningDashboardB() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()

        let focusButton = app.buttons["pipo.dashboard.focusGoal"].firstMatch
        XCTAssertTrue(focusButton.waitForExistence(timeout: 25),
                      "Focus goal must be a separately accessible button")
        XCTAssertTrue(focusButton.label.contains("Bali holiday"),
                      "The most advanced active personal goal should be featured")
        XCTAssertTrue(focusButton.label.contains("personal saving goal"), focusButton.label)
        XCTAssertTrue(focusButton.label.contains("recorded"), focusButton.label)
        XCTAssertTrue(focusButton.label.contains("percent complete"), focusButton.label)
        XCTAssertTrue(focusButton.label.contains("active"), focusButton.label)
        XCTAssertTrue(app.buttons["pipo.dashboard.recordSaving"].waitForExistence(timeout: 12),
                      "Record a saving must remain a separately accessible action")
        XCTAssertTrue(app.staticTexts["60% complete"].exists)
        attachOnboardingScreen("Dashboard B — returning user and featured goal")

        tapButton("pipo.dashboard.tab.goals")
        XCTAssertTrue(app.staticTexts["Saving goals"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Bandung trip"].exists)
        attachOnboardingScreen("Dashboard B — personal and group goals")

        tapButton("pipo.dashboard.tab.journey")
        XCTAssertTrue(app.staticTexts["Your journey"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["RECENT ACTIVITY"].exists)
        attachOnboardingScreen("Dashboard B — real recorded activity")

        tapButton("pipo.dashboard.journey.achievements")
        XCTAssertTrue(app.staticTexts["pipo.achievements.count"].waitForExistence(timeout: 12),
                      "The approved badge gallery must be accessible")
        attachOnboardingScreen("P0 — authentic achievement gallery")
        tapButton("Done")

        tapButton("pipo.dashboard.tab.profile")
        XCTAssertTrue(app.staticTexts["Your space"].waitForExistence(timeout: 12))
        attachOnboardingScreen("Dashboard B — profile data")
        XCTAssertTrue(app.staticTexts["pipo.dashboard.profile.xpLabel"].exists,
                      "Profile XP label must be independently accessible")

        tapButton("pipo.dashboard.tab.home")
        tapButton("pipo.dashboard.recordSaving")
        XCTAssertTrue(app.textFields["Amount in IDR"].waitForExistence(timeout: 12))
        typeText("Amount in IDR", value: "50000")
        tapButton("Save")
        XCTAssertTrue(app.buttons["View my achievements"].waitForExistence(timeout: 15))
        attachOnboardingScreen("Dashboard B — confirmed saving milestone")
    }


    /// #69: native-screen proof from the existing DEBUG-only account fixture.
    /// All saving records come from seeded SwiftData, not mock streak labels.
    func testIssue69SparkPerGoalHomeFocusAndDetail() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()

        let homeFocus = app.buttons["pipo.dashboard.focusGoal"].firstMatch
        XCTAssertTrue(homeFocus.waitForExistence(timeout: 25))
        XCTAssertTrue(homeFocus.label.contains("Bali holiday"))
        let activeChip = app.descendants(matching: .any)
            .matching(identifier: "pipo.spark.chip.Pending").firstMatch
        XCTAssertTrue(activeChip.waitForExistence(timeout: 15),
                      "Focus goal must show its still-open weekly period after the latest recorded saving")
        XCTAssertTrue(activeChip.label.contains("week"), activeChip.label)
        let homeSparkLabel = activeChip.label
        bringIntoView(activeChip)
        attachOnboardingScreen("Issue 69 — Focus goal pending period with three saved weeks")

        // The chip appears below the CTA. Scroll back toward the goal title
        // before tapping its navigation link on compact-screen simulators.
        for _ in 0..<6 {
            if homeFocus.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(homeFocus.isHittable)
        tapButton("pipo.dashboard.focusGoal")
        let heading = app.staticTexts["YOUR SAVING RHYTHM"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 15),
                      "Goal Detail must reuse the exact goal's streak projection")
        // SwiftUI's scroll-view subtree can defer access to the pill until it
        // is visible. Bring the section onscreen before querying its element.
        bringIntoView(heading)
        // ProgressView is retained in the SwiftUI source but may be grouped
        // inside the summary accessibility container on compact iPhones.
        let detailChip = app.descendants(matching: .any)
            .matching(identifier: "pipo.spark.chip.Pending").firstMatch
        XCTAssertTrue(detailChip.waitForExistence(timeout: 15),
                      "Goal Detail should show the same pending weekly state: \(app.debugDescription)")
        XCTAssertEqual(detailChip.label, homeSparkLabel,
                       "Home and Goal Detail must agree for the same goal")
        attachOnboardingScreen("Issue 69 — Goal Detail rhythm below manual progress")

        // Restart the synthetic in-memory fixture to navigate back to Home.
        // No real account, sync, XP or bank data is touched.
        app.terminate()
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()
        tapButton("pipo.dashboard.tab.goals")
        let secondary = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "New iPad")
        ).firstMatch
        XCTAssertTrue(secondary.waitForExistence(timeout: 20))
        XCTAssertTrue(secondary.label.contains("No streak yet"),
                      "Another goal must not inherit Bali's three weekly periods")
        let group = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Bandung trip")
        ).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 12))
        XCTAssertFalse(group.label.contains("streak"),
                       "Device-local group plan must not claim personal Spark")
        attachOnboardingScreen("Issue 69 — Other goals keep independent streak status")
    }

    /// #18: Exercise both Dashboard B metric cards at an iOS accessibility
    /// text category. This is a simulator layout/accessibility-tree proxy,
    /// not a substitute for VoiceOver focus order or physical-device review.
    func testDashboardMetricCardsAtAccessibilityTextSize() {
        continueAfterFailure = false
        app.launchArguments = [
            "-pipo-dashboard-qa",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityM"
        ]
        app.launch()

        let rhythm = app.buttons["pipo.dashboard.rhythm"].firstMatch
        let achievements = app.buttons["pipo.dashboard.achievements"].firstMatch
        XCTAssertTrue(rhythm.waitForExistence(timeout: 25),
                      "Rhythm metric card must remain reachable at large text")
        XCTAssertTrue(achievements.waitForExistence(timeout: 10),
                      "Achievement metric card must remain reachable at large text")

        bringIntoView(rhythm)
        XCTAssertTrue(rhythm.isHittable,
                      "The rhythm metric must remain a usable action")
        XCTAssertTrue(achievements.isHittable,
                      "The achievements metric must remain a usable action")
        XCTAssertTrue(rhythm.label.lowercased().contains("rhythm") ||
                      rhythm.label.lowercased().contains("pace"),
                      "Rhythm metric must expose a meaningful label")
        XCTAssertTrue(achievements.label.lowercased().contains("badges"),
                      "Achievement metric must announce the complete badge count")

        let window = app.windows.firstMatch
        XCTAssertLessThanOrEqual(rhythm.frame.maxX, window.frame.maxX + 1,
                                "Rhythm card extends beyond the screen width")
        XCTAssertLessThanOrEqual(achievements.frame.maxX, window.frame.maxX + 1,
                                "Achievement card extends beyond the screen width")
        attachOnboardingScreen("Issue 18 — Dashboard B metrics at accessibility text size")
    }

    /// #18 Dashboard B: goal rows announce their state, progress and recorded
    /// amount as one action, instead of relying on a context-menu long press.
    func testDashboardGoalRowsHaveAccountSafeAccessibilitySummary() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()

        tapButton("pipo.dashboard.tab.goals")
        let goal = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pipo.dashboard.goal.")
        ).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 20),
                      "A real account-owned goal row must be present")
        XCTAssertTrue(goal.label.contains("saving goal"), goal.label)
        XCTAssertTrue(goal.label.contains("recorded"), goal.label)
        XCTAssertTrue(goal.label.contains("percent complete"), goal.label)
    }

    /// #44 Approved Budget B visual and functional parity: one reused card
    /// in Goal Detail with the real SwiftData breakdown of a DEBUG-only goal.
    func testApprovedBudgetBreakdownBOnGoalDetail() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()

        let focus = app.buttons["pipo.dashboard.focusGoal"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 25))
        focus.tap()

        let backToGoals = app.buttons["Saving goals"].firstMatch
        XCTAssertTrue(backToGoals.waitForExistence(timeout: 15),
                      "Tapping the focus goal must navigate to the personal goal detail")
        XCTAssertTrue(app.staticTexts["BUDGET CATEGORIES"].waitForExistence(timeout: 15),
                      "Approved Budget B must appear in Goal Detail")
        XCTAssertTrue(app.staticTexts["Travel & stay"].exists,
                      "Actual item titles must be visible")
        XCTAssertTrue(app.staticTexts["TOTAL Rp6.000.000"].exists,
                      "Actual breakdown total must be visible")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "differs from this goal")
        ).firstMatch.exists,
                       "Matching breakdown must not report a mismatch")
        attachOnboardingScreen("Approved Budget B — saved goal detail")
    }

    /// #44: all 11 remaining selected card families are rendered from a
    /// DEBUG-only fixture and exported in sequential simulator screenshots.
    /// Money-out decision/input/impact are interactive drafts only.
    func testAllElevenApprovedCardFamilies() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa", "-pipo-allcards-qa"]
        app.launch()

        XCTAssertTrue(app.staticTexts["APPROVED PIPO CARDS · QA ONLY"]
                        .waitForExistence(timeout: 25),
                      "All-card QA board must load without a real account")

        let required = [
            "YOUR GOAL",
            "YOUR MILESTONE · EARNED",
            "YOUR STICKER ALBUM",
            "POSTCARD TO FUTURE ME",
            "GROUP GOAL · DEVICE ONLY",
            "YOUR RECORD / EDITABLE NOTE",
            "A CHANGE, NOT A RESET",
            "TWO WAYS FORWARD / YOU CHOOSE",
            "MY SAVING JOURNAL",
            "A GOAL YOU REACHED",
            "A NEW JOURNEY"
        ]
        var observed = Set<String>()
        let scroller = app.scrollViews.firstMatch
        XCTAssertTrue(scroller.exists)
        for page in 0..<12 {
            for heading in required where app.staticTexts[heading].exists {
                observed.insert(heading)
            }
            if page.isMultiple(of: 2) {
                attachOnboardingScreen("Pipo #44 - All Cards QA page \(page)")
            }
            if observed.count == required.count { break }
            scroller.swipeUp()
        }
        let missing = required.filter { !observed.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Approved card headings not rendered: \(missing)")
        let realMoneyOutAction = app.buttons["Confirm money withdrawal"].firstMatch
        XCTAssertFalse(realMoneyOutAction.exists,
                       "Draft-only cards must not expose real-money operations")
    }

    /// #48: Figma's one-third-height photo hero remains navigable without
    /// a sample image, and shows only one progress rail plus a sticky CTA.
    func testIssue48GoalDetailHeroAndEmptyMediaSafety() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()
        tapButton("pipo.dashboard.focusGoal")
        XCTAssertTrue(app.buttons["pipo.goal.heroBack"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pipo.goal.photoPicker"].exists)
        XCTAssertTrue(app.buttons["pipo.goal.recordSaving"].exists)
        XCTAssertFalse(app.buttons["pipo.goal.photoCounter"].exists,
                       "Pagination must not appear with zero photos")
        attachOnboardingScreen("Issue 48 — Goal hero no-cover, one progress rail")
    }

    /// Approved Option B: Goal Detail and Manage Plan use the SAME signed-in
    /// fixture; screenshots never splice the 25% B00 and 60% B01 mockups.
    /// No production data, plan fields, XP, or ledger are written by these taps.
    func testManagePlanV2OverviewFlexibleImpactReviewAndMoneyOutSafety() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()
        tapButton("pipo.dashboard.focusGoal")
        XCTAssertTrue(app.buttons["pipo.goal.recordSaving"].waitForExistence(timeout: 15))
        attachOnboardingScreen("Manage Plan V2 BEFORE — Goal Detail same fixture")
        tapButton("pipo.goal.planRevisionPreview")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Past savings and earned badges are preserved."].exists)
        XCTAssertTrue(app.progressIndicators.firstMatch.exists)
        XCTAssertFalse(app.buttons["pipo.plan.v2.primary"].isEnabled)
        attachOnboardingScreen("Manage Plan V2 B01 — Approved overview")
        tapButton("pipo.plan.v2.editRhythm")
        XCTAssertTrue(app.staticTexts["Find your pace."].waitForExistence(timeout: 10))
        attachOnboardingScreen("Manage Plan V2 B03 — Rhythm options")
        tapButton("pipo.plan.v2.rhythm.flexible")
        XCTAssertTrue(app.staticTexts["Save when it feels right."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Previous XP and saving history stay earned."].exists)
        XCTAssertTrue(app.buttons["pipo.plan.v2.primary"].isEnabled)
        attachOnboardingScreen("Manage Plan V2 B08 — Flexible no pressure")
        tapButton("pipo.plan.v2.primary")
        XCTAssertTrue(app.staticTexts["Here's what changes."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "No fixed schedule")
        ).firstMatch.exists)
        attachOnboardingScreen("Manage Plan V2 B04 — Flexible impact")
        tapButton("pipo.plan.v2.primary")
        XCTAssertTrue(app.staticTexts["Review your new plan."].waitForExistence(timeout: 10))
        let finalSave = app.buttons["pipo.plan.v2.primary"]
        XCTAssertTrue(finalSave.exists)
        XCTAssertFalse(finalSave.isEnabled, "Server-owned plan revision is not approved")
        XCTAssertTrue(app.staticTexts["The original plan remains active. This is a draft only."].exists)
        attachOnboardingScreen("Manage Plan V2 B05 — Unsaved review")
        tapButton("pipo.plan.v2.back")
        XCTAssertTrue(app.staticTexts["Here's what changes."].exists)
        tapButton("pipo.plan.v2.back")
        XCTAssertTrue(app.staticTexts["Save when it feels right."].exists)
        tapButton("pipo.plan.v2.back")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].exists)

        // Dirty draft cannot silently close; keep editing retains its inputs.
        tapButton("pipo.plan.v2.back")
        XCTAssertTrue(app.buttons["Discard draft"].waitForExistence(timeout: 10))
        tapButton("Keep editing")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].exists)
        tapButton("pipo.plan.v2.back")
        tapButton("Discard draft")
        XCTAssertTrue(app.buttons["pipo.goal.moneyOutPreview"].waitForExistence(timeout: 15))
        // The Goal Detail Record Saving footer is pinned above the scroll
        // content. A button can report isHittable even when its tap centre
        // intersects that footer. Validate a fully unobscured Money Out tap.
        tapButtonAboveSavingFooter("pipo.goal.moneyOutPreview")
        XCTAssertFalse(app.navigationBars["Record a saving"].exists,
                       "Money Out tap must not activate the pinned saving CTA")
        XCTAssertTrue(app.navigationBars["Money used elsewhere"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["pipo.card.moneyOut.amount"].exists)
        attachOnboardingScreen("Manage Plan V2 REGRESSION — Money Out preserved")
    }

    func testManagePlanV2TargetAndDateEditorsAreFocusedAndNonMutating() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()
        tapButton("pipo.dashboard.focusGoal")
        tapButton("pipo.goal.planRevisionPreview")
        tapButton("pipo.plan.v2.editTarget")
        XCTAssertTrue(app.staticTexts["Change the target."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["pipo.plan.v2.targetAmount"].exists)
        attachOnboardingScreen("Manage Plan V2 B02 — Focused target")
        // Keyboard can be shown without hiding target context or forcing a save.
        let field = app.textFields["pipo.plan.v2.targetAmount"]
        bringIntoView(field)
        field.tap()
        attachOnboardingScreen("Manage Plan V2 B10 — Keyboard safe target")
        tapButton("pipo.plan.v2.back")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].waitForExistence(timeout: 10))
        tapButton("pipo.plan.v2.editDate")
        XCTAssertTrue(app.staticTexts["Change the finish date."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.datePickers["pipo.plan.v2.finishDate"].exists ||
                      app.buttons["pipo.plan.v2.finishDate"].exists,
                      "The native date picker must remain VoiceOver discoverable")
        attachOnboardingScreen("Manage Plan V2 B13 — Finish date")
        XCTAssertFalse(app.buttons["pipo.plan.v2.primary"].isEnabled)
    }

    /// Automated accessibility-tree proxy at a large system text category.
    /// This proves discoverable labels, tappable targets and reachable native
    /// controls; actual VoiceOver speech/focus order and Switch Control still
    /// require a signed-device/manual accessibility session.
    func testGlobalV1AccessibilityLabelsAndTargetsAtLargeText() {
        continueAfterFailure = false
        // This DEBUG-only fixture does not authenticate or send cloud writes.
        // UICTContentSizeCategoryAccessibilityM is a supported large category.
        app.launchArguments = [
            "-pipo-dashboard-qa",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityM"
        ]
        app.launch()
        tapButton("pipo.dashboard.focusGoal")
        tapButtonAboveSavingFooter("pipo.goal.planRevisionPreview")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].waitForExistence(timeout: 15))

        let back = app.buttons["pipo.plan.v2.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertFalse(back.label.trimmingCharacters(in: .whitespaces).isEmpty,
                       "Back must have a spoken accessibility label")
        XCTAssertGreaterThanOrEqual(back.frame.height, 44,
            "Back control is below Pipo's 44pt accessibility target")
        let primary = app.buttons["pipo.plan.v2.primary"].firstMatch
        XCTAssertTrue(primary.exists)
        XCTAssertGreaterThanOrEqual(primary.frame.height, 44,
            "Primary action must remain a 44pt minimum target under large text")
        XCTAssertFalse(primary.label.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertFalse(primary.isEnabled,
            "Manage Plan remains preview-only, including accessibility sizes")

        let targetChoice = app.buttons["pipo.plan.v2.editTarget"].firstMatch
        XCTAssertTrue(targetChoice.exists)
        XCTAssertTrue(targetChoice.label.contains("Target & breakdown"),
            "Target editor must expose its actual visible action, not just a chevron")
        XCTAssertGreaterThanOrEqual(targetChoice.frame.height, 44)
        tapButton("pipo.plan.v2.editTarget")
        let targetField = app.textFields["pipo.plan.v2.targetAmount"].firstMatch
        XCTAssertTrue(targetField.waitForExistence(timeout: 10))
        XCTAssertTrue(targetField.label.contains("Target amount in"),
            "Amount entry must announce its currency to assistive technology")
        attachOnboardingScreen("Global V1 AX — large text target editor")
        tapButton("pipo.plan.v2.back")

        tapButton("pipo.plan.v2.editDate")
        let dateField = app.datePickers["pipo.plan.v2.finishDate"].firstMatch
        let dateButton = app.buttons["pipo.plan.v2.finishDate"].firstMatch
        XCTAssertTrue(dateField.exists || dateButton.exists,
            "Finish-date control must remain accessible at large text sizes")
        let nativeDate = dateField.exists ? dateField : dateButton
        XCTAssertFalse(nativeDate.label.trimmingCharacters(in: .whitespaces).isEmpty)
        attachOnboardingScreen("Global V1 AX — native date editor")
    }

    /// Legacy #42 regressions: both sheets still open, but neither can mutate
    /// account history or complete a financial write.
    func testIssue42PlanAndMoneyOutRemainReviewOnly() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-dashboard-qa"]
        app.launch()
        tapButton("pipo.dashboard.focusGoal")
        tapButton("pipo.goal.planRevisionPreview")
        XCTAssertTrue(app.staticTexts["Your plan, your pace."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["pipo.plan.v2.primary"].isEnabled)
        attachOnboardingScreen("Issue 42 — Approved V2 overview, no writes")
        tapButton("pipo.plan.v2.back")
        tapButton("pipo.goal.moneyOutPreview")
        XCTAssertTrue(app.navigationBars["Money used elsewhere"].waitForExistence(timeout: 12))
        attachOnboardingScreen("Issue 42 — Money Out input is visible")
        let input = app.textFields["pipo.card.moneyOut.amount"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 12))
        typeText("pipo.card.moneyOut.amount", value: "500000")
        tapButton("pipo.card.moneyOut.review")
        XCTAssertTrue(app.staticTexts["A CHANGE, NOT A RESET"]
                      .waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Saving changes isn't available yet"].exists)
        XCTAssertFalse(app.buttons["Saving changes isn't available yet"].isEnabled)
        attachOnboardingScreen("Issue 42 — Approved money-out review, no writes")
    }

    /// Non-destructive P0 simulator acceptance: sign-in availability and
    /// account deletion confirmation. The fixture is DEBUG-only and has no
    /// backend Auth session. NEVER tap the destructive submit action.
    func testP0AuthAndDeletionReviewGuards() {
        continueAfterFailure = false
        app.launchArguments = ["-pipo-auth-qa"]
        app.launch()

        let forgot = app.buttons["pipo.auth.forgotPassword"].firstMatch
        XCTAssertTrue(forgot.waitForExistence(timeout: 25),
                      "Email recovery must be available on the sign-in screen")
        XCTAssertFalse(app.buttons["Apple"].exists,
                       "Unconfigured Apple sign-in must stay unavailable")
        XCTAssertFalse(app.buttons["Google"].exists,
                       "Unconfigured Google sign-in must stay unavailable")
        forgot.tap()
        XCTAssertTrue(app.staticTexts[
            "Enter your email address to receive a reset link."
        ].waitForExistence(timeout: 10),
                      "Invalid email must fail locally, without sending mail")
        attachOnboardingScreen("P0 - Recovery entry and no social provider")
        app.terminate()

        // A dedicated Debug-only account fixture avoids depending on a
        // previous test having completed onboarding. It also starts with
        // *zero* goals in an in-memory store, without a real Auth session.
        app.launchArguments = ["-pipo-account-qa"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your first saving goal"].waitForExistence(timeout: 25),
                      "A new account without goals must reach the dashboard")
        tapButton("pipo.dashboard.tab.profile")
        XCTAssertTrue(app.staticTexts["Your space"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pipo.profile.signOut"].exists,
                      "Sign out must be visible for a user with no saving goal")
        tapButton("pipo.profile.privacyInformation")
        XCTAssertTrue(app.staticTexts["Your data in Pipo"].waitForExistence(timeout: 12),
                      "Privacy summary must be reachable from Profile")
        tapButton("pipo.privacy.done")
        tapButton("pipo.profile.deleteAccount")
        let submit = app.buttons["pipo.deleteAccount.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 15))
        XCTAssertFalse(submit.isEnabled, "Deletion must be disabled by default")
        let confirmation = app.textFields["pipo.deleteAccount.confirmation"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()
        confirmation.typeText("DELETE")
        XCTAssertTrue(submit.isEnabled,
                      "Only a fully typed confirmation may unlock deletion")
        attachOnboardingScreen("P0 - Typed delete confirmation, not submitted")
        tapButton("pipo.deleteAccount.cancel")
        XCTAssertTrue(app.buttons["pipo.profile.deleteAccount"].waitForExistence(timeout: 15),
                      "Cancel must preserve the user's Profile")
    }

    private func launchOnboarding() {
        app.launchArguments = ["-pipo-onboarding-qa"]
        app.launch()
    }

    /// View-level Pipo reactions intentionally lift and scale for a moment.
    /// Compare the settled resting state rather than a spring's intermediate frame.
    private func assertMascotSettlesToSize(
        _ expectedHeight: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mascot = app.buttons["pipo.greet"].firstMatch
        XCTAssertTrue(mascot.waitForExistence(timeout: 8), file: file, line: line)
        let deadline = Date().addingTimeInterval(4)
        var difference = abs(mascot.frame.height - expectedHeight)
        while difference >= 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            difference = abs(mascot.frame.height - expectedHeight)
        }
        XCTAssertLessThan(
            difference,
            2,
            "Pipo must return to the same resting height on each step",
            file: file,
            line: line
        )
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

    /// XCUIElement.isHittable can be true even when a button's tap center
    /// overlaps the pinned Record Saving footer on a compact device.
    private func tapButtonAboveSavingFooter(_ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Missing button: \(identifier)")
        let scroll = app.scrollViews.containing(.button, identifier: identifier).firstMatch
        XCTAssertTrue(scroll.exists, "Goal Detail scroll view is missing")
        let footer = app.buttons["pipo.goal.recordSaving"].firstMatch
        XCTAssertTrue(footer.exists, "Goal Detail sticky footer is missing")
        for _ in 0..<8 {
            let entirelyAboveFooter = button.frame.minY >= scroll.frame.minY + 8
                && button.frame.maxY <= footer.frame.minY - 12
            if button.isHittable && entirelyAboveFooter { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(button.isHittable && button.frame.minY >= scroll.frame.minY + 8
                      && button.frame.maxY <= footer.frame.minY - 12,
                      "Goal Detail action is obscured by the saving footer: \(app.debugDescription)")
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
