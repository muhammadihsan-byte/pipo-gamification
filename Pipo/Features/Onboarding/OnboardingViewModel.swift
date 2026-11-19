import Foundation
import Observation
import SwiftUI

/// A conversational introduction shown after an account first signs in.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case nickname
    case motivation
    case widget

    var number: Int { rawValue + 1 }
    var progress: Double { Double(number) / Double(Self.allCases.count) }
}

enum OnboardingMotivation: String, CaseIterable, Codable, Identifiable {
    case buildHabit
    case excitingGoal
    case feelInControl
    case exploring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buildHabit: "Build a better saving habit"
        case .excitingGoal: "Save for something exciting"
        case .feelInControl: "Feel more in control of money"
        case .exploring: "Just exploring for now"
        }
    }

    var symbol: String {
        switch self {
        case .buildHabit: "calendar.badge.checkmark"
        case .excitingGoal: "airplane"
        case .feelInControl: "wallet.pass.fill"
        case .exploring: "sparkles"
        }
    }

    var companionReply: String {
        switch self {
        case .buildHabit: "Small steps count. I'm with you."
        case .excitingGoal: "Ooh, we've got plans. I like that."
        case .feelInControl: "We'll take it one step at a time."
        case .exploring: "No rush. I'll show you around."
        }
    }

    var homeGreeting: String {
        switch self {
        case .buildHabit: "Small steps add up. Ready for one?"
        case .excitingGoal: "That dream deserves a plan."
        case .feelInControl: "Your pace, your progress."
        case .exploring: "Take a look around. No pressure."
        }
    }
}

/// Keep user preferences separate from financial data and plan creation.
/// Stored under an authenticated-user-specific key on this device.
struct OnboardingPersonalization: Codable, Equatable {
    var nickname: String
    var motivation: OnboardingMotivation?
    var viewedWidgetGuide: Bool
    var completedAt: Date
}

enum OnboardingProfileStore {
    private static func key(for userID: UUID) -> String {
        "pipo.onboarding.personalization.v1.\(userID.uuidString.lowercased())"
    }

    static func load(for userID: UUID) -> OnboardingPersonalization? {
        guard let data = UserDefaults.standard.data(forKey: key(for: userID)) else { return nil }
        return try? JSONDecoder().decode(OnboardingPersonalization.self, from: data)
    }

    @discardableResult
    static func save(_ personalization: OnboardingPersonalization, for userID: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(personalization) else { return false }
        UserDefaults.standard.set(data, forKey: key(for: userID))
        return true
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome
    var nickname = ""
    var motivation: OnboardingMotivation?

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func finish(viewedWidgetGuide: Bool) -> OnboardingPersonalization {
        OnboardingPersonalization(
            nickname: String(nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)),
            motivation: motivation,
            viewedWidgetGuide: viewedWidgetGuide,
            completedAt: Date()
        )
    }
}
