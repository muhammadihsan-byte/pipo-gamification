import SwiftUI
import UIKit

/// First-run onboarding only. Plan amounts, dates, invitations and account
/// creation remain in their existing product flows.
@MainActor
struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var mascotReaction: OnboardingPipoReaction = .acknowledge
    @State private var mascotReactionID = 0
    @State private var mascotReply: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onCompleted: (OnboardingCompletion) -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.step.showsProgress {
                OnboardingHeaderView(progress: viewModel.step.progress)
                    .padding(.bottom, 10)
            }

            ScrollView {
                VStack(spacing: 16) {
                    stepContent
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, viewModel.step == .welcome ? 32 : 12)
                .padding(.bottom, 32)
            }
            .id(viewModel.step) // Moving forward or back always starts at the top.
        }
        .background(
            LinearGradient(
                colors: [.white, PipoTheme.palePink.opacity(0.35), PipoTheme.cream],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .preferredColorScheme(.light)
        .onChange(of: viewModel.step) { _, next in
            mascotReply = nil
            mascotReaction = next == .preview ? .celebrate : .acknowledge
            if next == .preview { mascotReactionID += 1 }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            welcomeContent
        case .goal:
            questionContent(height: 132) {
                goalOptions
            }
        case .savingMode:
            questionContent(height: 160) {
                savingModeOptions
            }
        case .rhythm:
            questionContent(height: 150) {
                rhythmOptions
            }
        case .preview:
            previewContent
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 16) {
            Text("MEET YOUR SAVING BUDDY")
                .font(.caption.weight(.bold))
                .tracking(1.25)
                .foregroundStyle(PipoTheme.deepPink)

            mascot(height: 238)

            Text("Tap Pipo to say hi")
                .font(.caption.weight(.medium))
                .foregroundStyle(PipoTheme.muted)

            Text("Big plans start small.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(PipoTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Text("Pick a goal, find your pace, and make saving a little more fun.")
                .font(.body)
                .foregroundStyle(PipoTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PipoTheme.green)
                Text("No bank connection needed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white, in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private func questionContent<Content: View>(
        height: CGFloat,
        @ViewBuilder options: () -> Content
    ) -> some View {
        VStack(spacing: 16) {
            mascot(height: height)

            SpeechBubbleView(text: viewModel.question)
                .accessibilityAddTraits(.isHeader)

            if let mascotReply {
                Text(mascotReply)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PipoTheme.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .accessibilityLabel("Pipo says: \(mascotReply)")
            }

            options()
        }
    }

    private var goalOptions: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingGoal.allCases) { goal in
                Button {
                    optionTapped {
                        viewModel.selectedGoal = goal
                        mascotReaction = goal == .explore ? .reassure : .acknowledge
                        mascotReply = goal == .explore
                            ? "No rush. Have a look around."
                            : "That's a goal worth showing up for."
                    }
                } label: {
                    SelectableOptionCard(
                        symbol: goal.symbol,
                        title: goal.title,
                        selected: viewModel.selectedGoal == goal,
                        dashed: goal == .explore
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pipo.onboarding.goal.\(goal.rawValue)")
            }
        }
    }

    private var savingModeOptions: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingSavingMode.allCases) { mode in
                Button {
                    optionTapped {
                        viewModel.savingMode = mode
                        mascotReaction = .acknowledge
                        mascotReply = mode == .group
                            ? "A little teamwork. I like it."
                            : "Your goal, your pace."
                    }
                } label: {
                    SelectableOptionCard(
                        symbol: mode.symbol,
                        title: mode.title,
                        subtitle: mode.subtitle,
                        selected: viewModel.savingMode == mode
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pipo.onboarding.mode.\(mode.rawValue)")
            }

            Text("You can create both kinds of plans later.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rhythmOptions: some View {
        VStack(spacing: 12) {
            ForEach([SavingRhythm.daily, .weekly, .monthly, .flexible], id: \.self) { rhythm in
                Button {
                    optionTapped {
                        viewModel.rhythm = rhythm
                        mascotReaction = rhythm == .flexible ? .reassure : .celebrate
                        mascotReply = rhythm == .flexible
                            ? "No pressure. You decide when."
                            : "Nice. One step at a time."
                    }
                } label: {
                    SelectableOptionCard(
                        symbol: rhythmSymbol(rhythm),
                        title: rhythmTitle(rhythm),
                        subtitle: rhythmDescription(rhythm),
                        selected: viewModel.rhythm == rhythm
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pipo.onboarding.rhythm.\(rhythm.rawValue)")
            }
            Text("This is a starting preference, not a commitment.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewContent: some View {
        VStack(spacing: 18) {
            mascot(height: 204)

            Text("Your starting point")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PipoTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Text("A good start. Let's make it yours.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                previewRow(
                    symbol: "flag.fill",
                    title: "Goal",
                    value: viewModel.selectedGoal?.title ?? "Explore first"
                )
                Divider().padding(.horizontal, 16)
                previewRow(
                    symbol: "person.2.fill",
                    title: "Saving with",
                    value: viewModel.savingMode == .group ? "A group" : "Myself"
                )
                Divider().padding(.horizontal, 16)
                previewRow(
                    symbol: "calendar",
                    title: "Rhythm",
                    value: rhythmTitle(viewModel.rhythm)
                )
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(PipoTheme.border, lineWidth: 1)
            }

            Text(
                viewModel.selectedGoal == .explore
                    ? "Take a look around first. You can create a goal whenever you're ready."
                    : "Your saving plan isn't created yet. After signing in, you'll choose the amount and date."
            )
            .font(.footnote)
            .foregroundStyle(PipoTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func previewRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(PipoTheme.deepPink)
                .frame(width: 34, height: 34)
                .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
            Spacer(minLength: 6)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }

    private func mascot(height: CGFloat) -> some View {
        OnboardingPipoView(
            height: height,
            reaction: mascotReaction,
            reactionID: mascotReactionID
        )
        .accessibilityHint("Double tap Pipo to make him wave.")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if viewModel.step != .welcome {
                    Button("Back") {
                        viewModel.goBack()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityIdentifier("pipo.onboarding.back")
                }

                Button {
                    if viewModel.step == .preview {
                        onCompleted(viewModel.completion)
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            viewModel.advance()
                        }
                    }
                } label: {
                    Text(primaryTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(!viewModel.canContinue)
                .opacity(viewModel.canContinue ? 1 : 0.5)
                .accessibilityIdentifier("pipo.onboarding.continue")
            }

            if viewModel.step == .welcome {
                Button("I already have an account", action: onSignIn)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PipoTheme.muted)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("pipo.onboarding.signin")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 568)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.98))
        .overlay(alignment: .top) {
            PipoTheme.border.frame(height: 1)
        }
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .welcome: "Get started"
        case .goal, .savingMode, .rhythm: "Continue"
        case .preview: "Continue to account"
        }
    }

    private func optionTapped(_ selection: () -> Void) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8)) {
            selection()
            mascotReactionID += 1
        }
    }

    private func rhythmTitle(_ rhythm: SavingRhythm) -> String {
        switch rhythm {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .flexible: "Decide later"
        case .biWeekly: "Every two weeks"
        }
    }

    private func rhythmSymbol(_ rhythm: SavingRhythm) -> String {
        switch rhythm {
        case .daily: "sun.max.fill"
        case .weekly: "calendar"
        case .monthly: "calendar.badge.clock"
        case .flexible: "slider.horizontal.3"
        case .biWeekly: "calendar"
        }
    }

    private func rhythmDescription(_ rhythm: SavingRhythm) -> String {
        switch rhythm {
        case .daily: "A little at a time"
        case .weekly: "Once each week"
        case .monthly: "Around payday"
        case .flexible: "Set your pace after signing in"
        case .biWeekly: "Every other week"
        }
    }
}

#Preview {
    OnboardingContainerView(onCompleted: { _ in }, onSignIn: {})
}
