import Foundation
import SwiftUI
import XCTest
@testable import Pipo

/// Native component snapshots for Figma visual QA; this is not an end-to-end UI navigation test.
@MainActor
final class SavingTimelineSnapshotTests: XCTestCase {
    func testPersonalAndGroupTimelineAtRegularAndNarrowWidths() {
        for isGroup in [false, true] {
            for width in [CGFloat(390), CGFloat(320)] {
                let height: CGFloat = width == 390 ? 852 : 760
                let view = SavingTimelineSnapshotFixture(isGroup: isGroup)
                    .frame(width: width, height: height)
                let name = "\(isGroup ? "Group" : "Personal")-Timeline-\(Int(width))pt"
                guard let screenshot = renderInWindow(view, size: CGSize(width: width, height: height)) else {
                    XCTFail("\(name) did not render")
                    continue
                }

                XCTAssertEqual(screenshot.size.width, width, accuracy: 1)
                XCTAssertEqual(screenshot.size.height, height, accuracy: 1)
                XCTAssertTrue(hasRenderedBodyContent(screenshot), "\(name) contains no visible content above the footer")

                let attachment = XCTAttachment(image: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
    /// Approved B01: real SwiftUI/window layout at the Figma reference width
    /// and the 320pt compact-width acceptance size. Screenshots are review
    /// evidence; frame dimensions and non-blank body content are asserted.
    func testManagePlanV2OverviewAt393And320PointWidths() {
        let finish = Calendar.current.date(byAdding: .month, value: 4, to: .now)!
        let goal = PersonalGoal(
            title: "Bali holiday",
            category: .trip,
            targetAmount: 6_000_000,
            currentAmount: 3_600_000,
            subItems: [
                SubItem(title: "Flights", amount: 2_000_000),
                SubItem(title: "Accommodation", amount: 2_500_000),
                SubItem(title: "Activities", amount: 1_000_000),
                SubItem(title: "Other", amount: 500_000)
            ],
            startDate: .now,
            targetDate: finish,
            rhythm: .weekly,
            preferredSavingDay: 3
        )
        XCTAssertEqual(goal.progress, 0.6, accuracy: 0.0001)
        for width in [CGFloat(393), CGFloat(320)] {
            let height: CGFloat = width == 393 ? 956 : 760
            let name = "Manage-Plan-V2-B01-\(Int(width))pt"
            let scene = PipoManagePlanV2Sheet(goal: goal, onClose: {})
                .frame(width: width, height: height)
            guard let screenshot = renderInWindow(
                scene, size: CGSize(width: width, height: height)
            ) else {
                XCTFail(name + " did not render")
                continue
            }
            XCTAssertEqual(screenshot.size.width, width, accuracy: 1)
            XCTAssertEqual(screenshot.size.height, height, accuracy: 1)
            XCTAssertTrue(hasRenderedBodyContent(screenshot), name + " has a blank body")
            XCTAssertTrue(hasVisibleFooterClearance(screenshot),
                          name + " clips the footer action at the bottom edge")
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Dynamic Type accessibility acceptance is different from ordinary 320pt
    /// acceptance: text grows, the editor must scroll, and the primary action
    /// must remain fully inside both compact and standard-size viewports.
    /// This verifies layout, not VoiceOver speech or focus order.
    func testManagePlanV2AccessibilityTextAt320And393KeepsFooterVisible() {
        let owner = UUID()
        let goal = PersonalGoal(
            title: "Trip with a longer goal title", category: .trip,
            targetAmount: 1500.50, currentAmount: 100.25,
            currencyCode: "USD", targetMinorUnits: 150_050,
            recordedMinorUnits: 10_025,
            targetDate: Calendar.current.date(byAdding: .month, value: 4, to: .now)!,
            rhythm: .weekly, preferredSavingDay: 3, ownerUserID: owner
        )
        for width in [CGFloat(320), CGFloat(393)] {
            let height: CGFloat = width == 320 ? 760 : 956
            let name = "Manage-Plan-AX3-\(Int(width))pt"
            let content = PipoManagePlanV2Sheet(goal: goal, onClose: {})
                .environment(\.dynamicTypeSize, .accessibility3)
                .frame(width: width, height: height)
            guard let screenshot = renderInWindow(
                content, size: CGSize(width: width, height: height)
            ) else {
                XCTFail(name + " did not render")
                continue
            }
            XCTAssertEqual(screenshot.size.width, width, accuracy: 1)
            XCTAssertEqual(screenshot.size.height, height, accuracy: 1)
            XCTAssertTrue(hasRenderedBodyContent(screenshot),
                          name + " is blank under accessibility text")
            XCTAssertTrue(hasVisibleFooterClearance(screenshot),
                          name + " clips the primary action under accessibility text")
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Embed a fixed-size SwiftUI host as a child controller inside the live
    /// UIWindow. UIWindowScene is free to resize its root view to the simulator's
    /// physical dimensions; using a constrained child is necessary for genuine
    /// 320×760 / 393×956 SwiftUI layout measurements.
    ///
    /// Do not relax the existing bottom-clearance assertion: the returned
    /// screenshot must show the CTA fully inside the child viewport.
    private func renderInWindow<Content: View>(_ content: Content, size: CGSize) -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let previousKeyWindow = scene.windows.first(where: { $0.isKeyWindow })
        let container = UIViewController()
        container.view.backgroundColor = .white
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .white
        let window = UIWindow(windowScene: scene)
        window.rootViewController = container
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
        }

        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.widthAnchor.constraint(equalToConstant: size.width),
            host.view.heightAnchor.constraint(equalToConstant: size.height)
        ])
        host.didMove(toParent: container)
        container.view.setNeedsLayout()
        container.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        container.view.layoutIfNeeded()
        host.view.layoutIfNeeded()
        guard abs(host.view.bounds.width - size.width) < 1,
              abs(host.view.bounds.height - size.height) < 1 else { return nil }
        let target = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size).image { context in
            if !host.view.drawHierarchy(in: target, afterScreenUpdates: true) {
                host.view.layer.render(in: context.cgContext)
            }
        }
    }

    /// Detect the regression where the pale footer CTA extends beyond the
    /// screenshot boundary at 320pt. The bottom 2pt of the fixture must be
    /// white, with sufficient dark text rendered above it in the footer area.
    /// This complements (and never replaces) manual screenshot inspection.
    private func hasVisibleFooterClearance(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return false }
        let bottomY = max(0, height - max(2, Int(image.scale * 2)))
        for x in stride(from: width / 3, to: 2 * width / 3, by: 9) {
            let index = bottomY * bytesPerRow + x * 4
            // Previous 320pt snapshot had CTA cream (251,252,254) at
            // the last row: that is a clipped button, not bottom clearance.
            if pixels[index] < 254 || pixels[index + 1] < 254 || pixels[index + 2] < 254 {
                return false
            }
        }
        var hasFooterText = false
        for y in stride(from: Int(Double(height) * 0.88), to: bottomY, by: 3) {
            for x in stride(from: width / 4, to: 3 * width / 4, by: 5) {
                let index = y * bytesPerRow + x * 4
                if pixels[index] < 210 && pixels[index + 1] < 210 && pixels[index + 2] < 210 {
                    hasFooterText = true
                    break
                }
            }
            if hasFooterText { break }
        }
        return hasFooterText
    }

    /// Fail visibly blank screenshots even if image dimensions and XCTest attachment export pass.
    private func hasRenderedBodyContent(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return false }
        var contrastingSamples = 0
        for y in stride(from: 120, to: max(120, height - 120), by: 4) {
            for x in stride(from: 12, to: max(12, width - 12), by: 4) {
                let index = y * bytesPerRow + x * 4
                if pixels[index] < 220 || pixels[index + 1] < 220 || pixels[index + 2] < 220 {
                    contrastingSamples += 1
                    if contrastingSamples > 30 { return true }
                }
            }
        }
        return false
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
            PersonalPlanChoice(title: "Target date · selected", selected: true, action: {})
            SavingDateEditor(entry: $entry, start: start, calendar: calendar)
            PersonalPlanChoice(title: "Duration", selected: false, action: {})
            if isGroup {
                PersonalPlanNote(
                    title: "Plan starts · 25 October 2026",
                    message: "Aiming for 25 July 2027. That gives 10 planned contribution dates."
                )
                Text("Your target date is an intention, not a guaranteed finish. You can adjust it as your group’s plans change.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
            } else {
                Text("Aiming for 25 July 2027. Your date is an aspiration, not a promise — you can change it.")
                    .font(.caption)
                    .foregroundStyle(PersonalPlanStyle.muted)
            }
        } footer: {
            PersonalPlanActions(back: {}, title: "Continue", action: {})
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }
}
