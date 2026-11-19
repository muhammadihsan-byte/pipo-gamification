import SwiftUI
import UIKit

/// A one-time, authenticated introduction to Pipo, not a saving-plan wizard.
/// The optional widget guidance is informational: iOS installs widgets in its gallery.
@MainActor
struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var mascotReaction: OnboardingPipoReaction = .acknowledge
    @State private var mascotReactionID = 0
    @State private var mascotReply: String?
    @State private var showingWidgetGuide = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nicknameFocused: Bool

    // Same 126pt V4 hero size as the approved optional-widget screen.
    private let mascotHeight: CGFloat = 126

    let onCompleted: (OnboardingPersonalization) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: viewModel.step, onBack: back)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 18) {
                    stepContent
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .id(viewModel.step)
        }
        .background(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .preferredColorScheme(.light)
        .onChange(of: viewModel.step) { _, step in
            mascotReply = nil
            nicknameFocused = false
            mascotReaction = step == .widget ? .reassure : .acknowledge
            mascotReactionID += 1
        }
        .sheet(isPresented: $showingWidgetGuide) {
            widgetGuide
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome: welcomeContent
        case .nickname: nicknameContent
        case .motivation: motivationContent
        case .widget: widgetContent
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 16) {
            Text("YOUR SAVING BUDDY")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(PipoTheme.deepPink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Little steps. Big dreams.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(PipoTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            companionDialogue("Hey! I'm Pipo. Want to make saving a little more fun?")

            Text("Tap Pipo to wave hello.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("No pressure. We'll figure things out together.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
        }
    }

    private var nicknameContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            companionDialogue("What should I call you?", reply: mascotReply)

            Text("YOUR NAME")
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PipoTheme.muted)
                .padding(.top, 8)

            TextField("e.g. Alex", text: $viewModel.nickname)
                .focused($nicknameFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { nicknameFocused = false }
                .onChange(of: viewModel.nickname) { _, name in
                    if name.count > 32 { viewModel.nickname = String(name.prefix(32)) }
                    let trimmed = viewModel.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    mascotReply = trimmed.isEmpty ? nil : "Nice to meet you, \(trimmed)!"
                }
                .font(.body)
                .padding(.horizontal, 18)
                .frame(minHeight: 60)
                .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(PipoTheme.border, lineWidth: 1)
                }
                .accessibilityIdentifier("pipo.onboarding.nickname")

            Text("A nickname is fine. You can change this anytime.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)

        }
    }

    private var motivationContent: some View {
        VStack(spacing: 14) {
            companionDialogue("What brings you to Pipo?", reply: mascotReply)

            ForEach(OnboardingMotivation.allCases) { motivation in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.motivation = motivation
                        mascotReply = motivation.companionReply
                        mascotReaction = motivation == .feelInControl || motivation == .exploring
                            ? .reassure : .celebrate
                        mascotReactionID += 1
                    }
                } label: {
                    SelectableOptionCard(
                        symbol: motivation.symbol,
                        title: motivation.title,
                        selected: viewModel.motivation == motivation
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pipo.onboarding.motivation.\(motivation.rawValue)")
                .accessibilityAddTraits(viewModel.motivation == motivation ? [.isSelected] : [])
            }

        }
    }

    private var widgetContent: some View {
        VStack(spacing: 17) {
            companionDialogue("Want Pipo on your Home Screen?")

            Text("See your saving progress without opening the app.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                widgetPreviewSmall
                widgetPreviewMedium
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            Text("Optional. Add a widget anytime from the iPhone Home Screen gallery.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var widgetPreviewSmall: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image("PipoV4Neutral")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Pipo").font(.subheadline.bold())
            }
            Spacer(minLength: 4)
            Text("Day one starts here")
                .font(.footnote.weight(.semibold))
            Text("Your journey awaits.")
                .font(.caption2)
                .foregroundStyle(PipoTheme.muted)
        }
        .foregroundStyle(PipoTheme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 154, maxHeight: 154)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(PipoTheme.border, lineWidth: 1)
        }
        .accessibilityLabel("Small Pipo widget preview. Day one starts here.")
    }

    private var widgetPreviewMedium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image("PipoV4Neutral")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Pipo").font(.subheadline.bold())
            }
            Spacer(minLength: 4)
            Text("No saving goal yet")
                .font(.footnote.weight(.semibold))
            Text("Start whenever you're ready.")
                .font(.caption2)
                .foregroundStyle(PipoTheme.muted)
        }
        .foregroundStyle(PipoTheme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 154, maxHeight: 154)
        .background(PipoTheme.cream, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(PipoTheme.border, lineWidth: 1)
        }
        .accessibilityLabel("Medium Pipo widget preview. No saving goal yet.")
    }

    private var widgetGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Pipo to your Home Screen")
                .font(.title2.bold())
                .foregroundStyle(PipoTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Text("You can do this anytime. No setup is required to use Pipo.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)

            VStack(alignment: .leading, spacing: 13) {
                guideRow("1", "Touch and hold an empty area on your Home Screen.")
                guideRow("2", "Tap Edit, then Add Widget.")
                guideRow("3", "Search for Pipo, pick a size, and tap Add Widget.")
            }

            Spacer(minLength: 4)

            Button {
                showingWidgetGuide = false
                finish(viewedWidgetGuide: true)
            } label: {
                Text("Go to Home")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("pipo.onboarding.widget.done")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
    }

    private func guideRow(_ number: String, _ instruction: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(PipoTheme.pink, in: Circle())
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(PipoTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Keeps Pipo at the same actual size and places the connected speech
    /// bubble immediately beneath him on every onboarding step.
    private func companionDialogue(_ prompt: String, reply: String? = nil) -> some View {
        VStack(spacing: 6) {
            OnboardingPipoView(
                height: mascotHeight,
                reaction: mascotReaction,
                reactionID: mascotReactionID
            )
            .accessibilityHint("Double tap Pipo to make him wave.")

            SpeechBubbleView(text: prompt, response: reply)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Button {
                switch viewModel.step {
                case .widget:
                    showingWidgetGuide = true
                default:
                    nicknameFocused = false
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.advance()
                    }
                }
            } label: {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityIdentifier("pipo.onboarding.continue")

            if viewModel.step == .nickname || viewModel.step == .motivation {
                Button("Skip for now") {
                    nicknameFocused = false
                    if viewModel.step == .nickname { viewModel.nickname = "" }
                    if viewModel.step == .motivation { viewModel.motivation = nil }
                    viewModel.advance()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PipoTheme.muted)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pipo.onboarding.skip")
            } else if viewModel.step == .widget {
                Button("Maybe later — go to Home") {
                    finish(viewedWidgetGuide: false)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PipoTheme.muted)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pipo.onboarding.widget.skip")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 568)
        .frame(maxWidth: .infinity)
        .background(.white)
        .overlay(alignment: .top) {
            PipoTheme.border.frame(height: 1)
        }
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .welcome: "Let's do this"
        case .nickname, .motivation: "Continue"
        case .widget: "Show me how"
        }
    }

    private func back() {
        nicknameFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            viewModel.goBack()
        }
    }

    private func finish(viewedWidgetGuide: Bool) {
        onCompleted(viewModel.finish(viewedWidgetGuide: viewedWidgetGuide))
    }
}

#Preview {
    OnboardingContainerView(onCompleted: { _ in })
}
