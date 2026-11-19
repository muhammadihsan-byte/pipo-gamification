import Observation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case splash = 1
    case welcome
    case mascotIntro
    case expectations
    case goal
    case savingMode
    case loading
    case habit
    case motivation
    case rhythm
    case reinforcement
    case notifications
    case widget
    case vision
    case plan

    var progress: Double {
        switch self {
        case .splash, .welcome, .mascotIntro, .expectations: 0
        case .goal: 0.2
        case .savingMode: 0.4
        case .loading: 0.5
        case .habit: 0.6
        case .motivation: 0.8
        case .rhythm: 0.9
        case .reinforcement: 0.93
        case .notifications: 0.95
        case .widget: 0.97
        case .vision: 0.99
        case .plan: 1
        }
    }

    var showsProgress: Bool {
        rawValue >= Self.goal.rawValue
    }
}

enum OnboardingGoal: String, CaseIterable, Identifiable {
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
        case .explore: "Explore first / Decide later"
        }
    }

    var symbol: String {
        switch self {
        case .wedding: "💍"
        case .trip: "✈️"
        case .gadget: "📱"
        case .emergency: "🛡️"
        case .home: "🏠"
        case .explore: "🌱"
        }
    }

    var category: GoalCategory? {
        switch self {
        case .wedding: .gift
        case .trip: .trip
        case .gadget: .gadget
        case .emergency: .debt
        case .home: .house
        case .explore: nil
        }
    }
}

enum OnboardingSavingMode: String, CaseIterable, Identifiable {
    case personal
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal Plan"
        case .group: "Group Saving (Pipo)"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: "Just me, my pace"
        case .group: "Save together with partner or friends"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "👤"
        case .group: "🤝"
        }
    }
}

enum OnboardingHabit: String, CaseIterable, Identifiable {
    case beginner
    case leftover
    case notes
    case budget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "I'm brand new to saving"
        case .leftover: "I save whenever I have leftover cash"
        case .notes: "I use notes or spreadsheets"
        case .budget: "I already follow a strict budget"
        }
    }

    var signalLevel: Int {
        switch self {
        case .beginner: 1
        case .leftover: 2
        case .notes: 3
        case .budget: 4
        }
    }
}

enum OnboardingMotivation: String, CaseIterable, Identifiable {
    case peace
    case discipline
    case accountability
    case guiltFree
    case habit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peace: "Peace of mind"
        case .discipline: "Staying disciplined"
        case .accountability: "Accountability with my partner/group"
        case .guiltFree: "Treating myself guilt-free"
        case .habit: "Building a lifelong habit"
        }
    }

    var symbol: String {
        switch self {
        case .peace: "🕊️"
        case .discipline: "🎯"
        case .accountability: "🤝"
        case .guiltFree: "✨"
        case .habit: "🚀"
        }
    }
}

enum OnboardingPlan: String, CaseIterable, Identifiable {
    case plus
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plus: "Pipo Plus"
        case .free: "Start for Free"
        }
    }

    var subtitle: String {
        switch self {
        case .plus: "Unlimited group plans, custom mascot outfits, zero ads"
        case .free: "Core personal & group saving features"
        }
    }
}

struct OnboardingCompletion {
    let goalCategory: GoalCategory?
    let goalTitle: String?
    let rhythm: SavingRhythm?
    let isPlusSelected: Bool
    let isGroupSaving: Bool
}

@MainActor
@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .splash
    var selectedGoal: OnboardingGoal?
    var savingMode: OnboardingSavingMode?
    var habit: OnboardingHabit?
    var motivations: Set<OnboardingMotivation> = []
    var rhythm: SavingRhythm?
    var plan: OnboardingPlan?

    var canContinue: Bool {
        switch step {
        case .goal: selectedGoal != nil
        case .savingMode: savingMode != nil
        case .habit: habit != nil
        case .motivation: !motivations.isEmpty
        case .rhythm: rhythm != nil
        case .plan: plan != nil
        default: true
        }
    }

    var question: String {
        switch step {
        case .goal: "What are you saving for first?"
        case .savingMode:
            selectedGoal == .explore
                ? "How do you plan to use Pipo?"
                : "How do you want to save for this?"
        case .loading: "One moment! I'm putting your plan together."
        case .habit: "How do you usually track your savings?"
        case .motivation: "Why is this goal important to you?"
        case .rhythm: "What's your saving rhythm?"
        case .reinforcement where rhythm == .daily:
            "Daily saving helps little steps add up to big progress!"
        case .reinforcement where rhythm == .weekly:
            "Saving weekly boosts goal completion by 3x!"
        case .reinforcement where rhythm == .monthly:
            "A payday routine makes saving feel effortless!"
        case .reinforcement: "A steady rhythm makes every goal feel closer!"
        case .notifications: "I'll nudge you on payday so you never break your streak!"
        case .widget: "I'll cheer you on right from your home screen!"
        case .vision: "Here's what you can achieve in 3 months!"
        case .plan: "How do you want to get started?"
        default: ""
        }
    }

    var loadingTitle: String {
        selectedGoal == .explore ? "SETTING UP YOUR SPACE..." : "BUILDING YOUR PLAN..."
    }

    func advance() {
        guard canContinue, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func toggle(_ motivation: OnboardingMotivation) {
        if motivations.contains(motivation) {
            motivations.remove(motivation)
        } else {
            motivations.insert(motivation)
        }
    }

    var completion: OnboardingCompletion {
        let isPersonalPlan = savingMode == .personal
        let shouldCreateGoal = isPersonalPlan && selectedGoal != .explore
        return OnboardingCompletion(
            goalCategory: shouldCreateGoal ? selectedGoal?.category : nil,
            goalTitle: shouldCreateGoal ? selectedGoal?.title : nil,
            rhythm: shouldCreateGoal ? rhythm : nil,
            isPlusSelected: plan == .plus,
            isGroupSaving: savingMode == .group
        )
    }
}
