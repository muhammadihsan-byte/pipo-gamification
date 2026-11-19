import Observation
import SwiftUI

/// Four short questions after Welcome, followed by an honest preview.
/// Authentication happens in RootView after the user confirms the preview.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case goal
    case savingMode
    case rhythm
    case preview

    var showsProgress: Bool { self != .welcome }
    var progress: Double { Double(rawValue) / Double(Self.allCases.count - 1) }
}

enum OnboardingGoal: String, CaseIterable, Identifiable, Codable {
    case wedding
    case trip
    case gadget
    case emergency
    case home
    case explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wedding: "Wedding & Future"
        case .trip: "Dream Trip"
        case .gadget: "New Gadget"
        case .emergency: "Emergency Fund"
        case .home: "Home & Living"
        case .explore: "Explore first"
        }
    }

    /// System symbols are more visually consistent than mixed emoji illustrations.
    var symbol: String {
        switch self {
        case .wedding: "heart.fill"
        case .trip: "airplane"
        case .gadget: "iphone.gen3"
        case .emergency: "cross.case.fill"
        case .home: "house.fill"
        case .explore: "sparkles"
        }
    }

    var category: GoalCategory? {
        switch self {
        case .wedding: .gift
        case .trip: .trip
        case .gadget: .gadget
        case .emergency: .other // Never label an emergency fund as debt.
        case .home: .house
        case .explore: nil
        }
    }
}

enum OnboardingSavingMode: String, CaseIterable, Identifiable, Codable {
    case personal
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal Saving"
        case .group: "Group Saving"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: "Your goal, your pace"
        case .group: "Plan together with someone you trust"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "person.fill"
        case .group: "person.2.fill"
        }
    }
}

/// Only genuine setup choices are handed off. No paid offer or notification
/// permission is requested during first-run onboarding.
struct OnboardingCompletion: Codable {
    let goalCategory: GoalCategory?
    let goalTitle: String?
    let rhythm: SavingRhythm?
    let isPlusSelected: Bool
    let isGroupSaving: Bool
}

@MainActor
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome
    var selectedGoal: OnboardingGoal?
    var savingMode: OnboardingSavingMode?
    var rhythm: SavingRhythm = .flexible

    var canContinue: Bool {
        switch step {
        case .goal: selectedGoal != nil
        case .savingMode: savingMode != nil
        default: true
        }
    }

    var question: String {
        switch step {
        case .welcome: ""
        case .goal: "What would you like to save for?"
        case .savingMode: "Going solo, or saving together?"
        case .rhythm: "What pace feels right for you?"
        case .preview: "Here's your starting point."
        }
    }

    func advance() {
        guard canContinue, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    var completion: OnboardingCompletion {
        let shouldPrefill = savingMode == .personal && selectedGoal != .explore
        return OnboardingCompletion(
            goalCategory: shouldPrefill ? selectedGoal?.category : nil,
            goalTitle: shouldPrefill ? selectedGoal?.title : nil,
            rhythm: shouldPrefill ? rhythm : nil,
            isPlusSelected: false,
            isGroupSaving: savingMode == .group && selectedGoal != .explore
        )
    }
}
