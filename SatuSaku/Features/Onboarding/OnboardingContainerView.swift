import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var mascotBounce = false
    @State private var hasAnimatedSplash = false
    @State private var notificationError: String?
    @State private var isShowingWidgetInstructions = false

    let onCompleted: (OnboardingCompletion) -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.step.showsProgress {
                OnboardingHeaderView(
                    progress: viewModel.step.progress,
                    mascotBounce: mascotBounce
                )
                    .padding(.bottom, 14)
            }

            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.step.showsProgress {
                        SpeechBubbleView(text: viewModel.question)
                            .padding(.horizontal, 24)
                    }
                    stepContent
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.top, viewModel.step.showsProgress ? 4 : 20)
            }
        }
        .background(
            LinearGradient(
                colors: [.white, SatuSakuTheme.mint.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.step)
        .task(id: viewModel.step) {
            guard viewModel.step == .splash || viewModel.step == .loading else { return }
            let delay: UInt64 = viewModel.step == .splash ? 1_500_000_000 : 1_800_000_000
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    advance()
                }
            } catch {
                return
            }
        }
        .alert(
            "Notifications unavailable",
            isPresented: Binding(
                get: { notificationError != nil },
                set: { if !$0 { notificationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                notificationError = nil
            }
        } message: {
            Text(notificationError ?? "")
        }
        .onAppear {
            hasAnimatedSplash = true
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .splash:
            splashContent
        case .welcome:
            welcomeContent
        case .mascotIntro:
            mascotIntroContent
        case .expectations:
            expectationsContent
        case .goal:
            goalOptions
        case .savingMode:
            savingModeOptions
        case .loading:
            loadingContent
        case .habit:
            habitOptions
        case .motivation:
            motivationOptions
        case .rhythm:
            rhythmOptions
        case .reinforcement:
            reinforcementContent
        case .notifications:
            notificationContent
        case .widget:
            widgetContent
        case .vision:
            visionContent
        case .plan:
            planOptions
        }
    }

    private var splashContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 18)
            PipoMascotView(state: .celebrating)
                .frame(width: 210, height: 210)
                .scaleEffect(hasAnimatedSplash ? 1 : 0.72)
                .animation(.spring(response: 0.72, dampingFraction: 0.48), value: hasAnimatedSplash)
            HStack(spacing: 8) {
                Text("Pipo")
                Text("/")
                    .foregroundStyle(SatuSakuTheme.pink)
                Text("SatuSaku")
            }
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(SatuSakuTheme.ink)
            .opacity(hasAnimatedSplash ? 1 : 0)
            .offset(y: hasAnimatedSplash ? 0 : 10)
            .animation(.easeOut(duration: 0.7).delay(0.25), value: hasAnimatedSplash)
            Text("A little saving, a lot of possibility.")
                .font(.subheadline)
                .foregroundStyle(SatuSakuTheme.muted)
            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity, minHeight: 390)
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.step == .splash else { return }
            withAnimation(.spring()) { advance() }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 18) {
            PipoMascotView(state: .idle)
                .frame(height: 245)
                .frame(maxWidth: .infinity)
                .scaleEffect(mascotBounce ? 1.03 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.48), value: mascotBounce)
            Text("Save together.\nReach your goals.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(SatuSakuTheme.ink)
        }
    }

    private var mascotIntroContent: some View {
        VStack(spacing: 18) {
            mascotIllustration(state: .happy, height: 250)
                .overlay(alignment: .topTrailing) {
                    Text("👋")
                        .font(.system(size: 42))
                        .offset(x: -34, y: 28)
                        .accessibilityHidden(true)
                }
            SpeechBubbleView(text: "Hi there! I'm Pipo!")
        }
    }

    private var expectationsContent: some View {
        VStack(spacing: 18) {
            mascotIllustration(state: .idle, height: 230)
                .rotationEffect(.degrees(-4))
            SpeechBubbleView(text: "Just 4 quick questions before we build your first saving plan!")
        }
    }

    private var goalOptions: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingGoal.allCases) { goal in
                Button {
                    optionTapped { viewModel.selectedGoal = goal }
                } label: {
                    SelectableOptionCard(
                        symbol: goal.symbol,
                        title: goal.title,
                        selected: viewModel.selectedGoal == goal,
                        dashed: goal == .explore
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goal.title)
            }
        }
    }

    private var savingModeOptions: some View {
        VStack(spacing: 12) {
            ForEach(OnboardingSavingMode.allCases) { mode in
                Button {
                    optionTapped { viewModel.savingMode = mode }
                } label: {
                    SelectableOptionCard(
                        symbol: mode.symbol,
                        title: mode.title,
                        subtitle: mode.subtitle,
                        selected: viewModel.savingMode == mode
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title), \(mode.subtitle)")
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 18) {
            mascotIllustration(state: .celebrating, height: 220)
                .overlay(alignment: .bottomTrailing) {
                    Text("🐷")
                        .font(.system(size: 54))
                        .padding(10)
                        .background(.white, in: Circle())
                        .overlay { Circle().strokeBorder(SatuSakuTheme.palePink, lineWidth: 2) }
                        .offset(x: -16, y: -5)
                }
            Text(viewModel.loadingTitle)
                .font(.headline.weight(.heavy))
                .tracking(1)
                .foregroundStyle(SatuSakuTheme.green)
            ProgressView()
                .controlSize(.large)
                .tint(SatuSakuTheme.pink)
            Text("Join thousands reaching their targets faster with Pipo!")
                .font(.subheadline)
                .foregroundStyle(SatuSakuTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var habitOptions: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingHabit.allCases) { habit in
                Button {
                    optionTapped { viewModel.habit = habit }
                } label: {
                    HStack(spacing: 14) {
                        SignalBarsView(level: habit.signalLevel)
                            .frame(width: 42, height: 34)
                        Text(habit.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(viewModel.habit == habit ? SatuSakuTheme.deepPink : SatuSakuTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if viewModel.habit == habit {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SatuSakuTheme.pink)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(
                        viewModel.habit == habit ? SatuSakuTheme.palePink : .white,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                viewModel.habit == habit ? SatuSakuTheme.pink : SatuSakuTheme.border,
                                lineWidth: viewModel.habit == habit ? 1.8 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.habit == habit ? .isSelected : [])
            }
        }
    }

    private var motivationOptions: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingMotivation.allCases) { motivation in
                Button {
                    optionTapped { viewModel.toggle(motivation) }
                } label: {
                    SelectableOptionCard(
                        symbol: motivation.symbol,
                        title: motivation.title,
                        selected: viewModel.motivations.contains(motivation)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(motivation.title)
            }
        }
    }

    private var rhythmOptions: some View {
        VStack(spacing: 12) {
            rhythmCard(.daily, subtitle: "Casual", symbol: "☀️")
            rhythmCard(.weekly, subtitle: "Recommended", symbol: "📅", badge: "RECOMMENDED")
            rhythmCard(.monthly, subtitle: "Focused", symbol: "💪")
        }
    }

    private var reinforcementContent: some View {
        VStack(spacing: 18) {
            mascotIllustration(state: .celebrating, height: 265)
                .overlay(alignment: .topTrailing) {
                    Text("✨")
                        .font(.system(size: 36))
                        .offset(x: -34, y: 32)
                        .accessibilityHidden(true)
                }
            Text("Your rhythm, your progress.")
                .font(.title2.weight(.bold))
                .foregroundStyle(SatuSakuTheme.ink)
                .multilineTextAlignment(.center)
        }
    }

    private var notificationContent: some View {
        VStack(spacing: 20) {
            mascotIllustration(state: .happy, height: 200)
                .overlay(alignment: .topTrailing) {
                    Text("👍")
                        .font(.system(size: 38))
                        .offset(x: -30, y: 28)
                        .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 12) {
                Label("SatuSaku", systemImage: "app.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SatuSakuTheme.muted)
                Text("A little reminder for your goal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SatuSakuTheme.ink)
                Text("It's your saving day! Add a little to your goal and keep that streak going.")
                    .font(.subheadline)
                    .foregroundStyle(SatuSakuTheme.muted)
                Text("now")
                    .font(.caption)
                    .foregroundStyle(SatuSakuTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
            }
        }
    }

    private var widgetContent: some View {
        VStack(spacing: 16) {
            phonePreview
            Text("Add the SatuSaku widget any time from your Home Screen's edit mode.")
                .font(.subheadline)
                .foregroundStyle(SatuSakuTheme.muted)
                .multilineTextAlignment(.center)
        }
        .alert("Add SatuSaku to your Home Screen", isPresented: $isShowingWidgetInstructions) {
            Button("Continue") { advance() }
        } message: {
            Text("Touch and hold your Home Screen, tap Edit, then Add Widget and choose SatuSaku.")
        }
    }

    private var phonePreview: some View {
        VStack(spacing: 18) {
            HStack {
                Text("9:41")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SatuSakuTheme.ink)
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SatuSakuTheme.ink)

            widgetPreview

            Capsule()
                .fill(SatuSakuTheme.ink.opacity(0.75))
                .frame(width: 92, height: 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: 350)
        .background(SatuSakuTheme.cream, in: RoundedRectangle(cornerRadius: 34))
        .overlay {
            RoundedRectangle(cornerRadius: 34)
                .strokeBorder(SatuSakuTheme.ink.opacity(0.2), lineWidth: 2)
        }
        .shadow(color: SatuSakuTheme.ink.opacity(0.12), radius: 12, y: 6)
    }

    private var widgetPreview: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(SatuSakuTheme.mint)
                    .frame(width: 90, height: 104)
                PipoMascotView(state: .happy)
                    .frame(width: 90, height: 92)
                    .offset(x: 3, y: 6)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Dream Trip")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SatuSakuTheme.ink)
                HStack {
                    Text("Progress")
                    Spacer()
                    Text("65%")
                }
                .font(.caption)
                .foregroundStyle(SatuSakuTheme.muted)
                ProgressView(value: 0.65)
                    .tint(SatuSakuTheme.green)
                Label("7 day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SatuSakuTheme.pink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
        }
        .shadow(color: SatuSakuTheme.ink.opacity(0.1), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SatuSaku home screen widget preview, Dream Trip at 65 percent, 7 day streak")
    }

    private var visionContent: some View {
        VStack(spacing: 12) {
            mascotIllustration(state: .celebrating, height: 205)
                .overlay(alignment: .topTrailing) {
                    Text("🏅")
                        .font(.system(size: 44))
                        .offset(x: -34, y: 26)
                        .accessibilityHidden(true)
                }
            visionRow(symbol: "🔥", title: "Build an unbreakable streak", subtitle: "Daily or weekly check-ins")
            visionRow(symbol: "💰", title: "Hit your first milestone", subtitle: "Smart automated breakdowns")
            visionRow(symbol: "🏆", title: "Unlock Pipo badges & rewards", subtitle: "Celebrate every deposit")
        }
    }

    private var planOptions: some View {
        VStack(spacing: 12) {
            Button {
                optionTapped { viewModel.plan = .plus }
            } label: {
                SelectableOptionCard(
                    symbol: "✨",
                    title: OnboardingPlan.plus.title,
                    subtitle: OnboardingPlan.plus.subtitle,
                    selected: viewModel.plan == .plus,
                    badge: "RECOMMENDED"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pipo Plus, recommended. \(OnboardingPlan.plus.subtitle)")

            Button {
                optionTapped { viewModel.plan = .free }
            } label: {
                SelectableOptionCard(
                    symbol: "🌱",
                    title: OnboardingPlan.free.title,
                    subtitle: OnboardingPlan.free.subtitle,
                    selected: viewModel.plan == .free
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(OnboardingPlan.free.title). \(OnboardingPlan.free.subtitle)")
        }
    }

    private var footer: some View {
        Group {
            switch viewModel.step {
            case .splash:
                actionButton("CONTINUE") { advance() }
            case .welcome:
                VStack(spacing: 10) {
                    actionButton("GET STARTED") { advance() }
                    Button("I ALREADY HAVE AN ACCOUNT", action: onSignIn)
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(SatuSakuTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
            case .mascotIntro, .expectations, .reinforcement, .vision:
                actionButton("CONTINUE") { advance() }
            case .goal, .savingMode, .habit, .motivation:
                actionButton("CONTINUE", isDisabled: !viewModel.canContinue) { advance() }
            case .loading:
                EmptyView()
            case .rhythm:
                actionButton("I'M COMMITTED", isDisabled: !viewModel.canContinue) { advance() }
            case .notifications:
                actionButton("REMIND ME TO SAVE") { requestNotificationsAndContinue() }
            case .widget:
                VStack(spacing: 8) {
                    actionButton("ADD WIDGET") { isShowingWidgetInstructions = true }
                    Button("NOT NOW") { advance() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SatuSakuTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
            case .plan:
                actionButton("CONTINUE", isDisabled: !viewModel.canContinue) {
                    onCompleted(viewModel.completion)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: 568)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.97))
        .overlay(alignment: .top) {
            SatuSakuTheme.border.frame(height: 1)
        }
    }

    private func actionButton(
        _ title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .tracking(0.6)
        }
        .buttonStyle(TactileButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    private func mascotIllustration(state: PipoMascotState, height: CGFloat) -> some View {
        PipoMascotView(state: state)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .offset(y: mascotBounce ? -5 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.48), value: mascotBounce)
    }

    private func rhythmCard(
        _ rhythm: SavingRhythm,
        subtitle: String,
        symbol: String,
        badge: String? = nil
    ) -> some View {
        let selected = viewModel.rhythm == rhythm
        return Button {
            optionTapped { viewModel.rhythm = rhythm }
        } label: {
            SelectableOptionCard(
                symbol: symbol,
                title: rhythm.title,
                subtitle: subtitle,
                selected: selected,
                badge: badge
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rhythm.title), \(subtitle)")
    }

    private func visionRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Text(symbol)
                .font(.system(size: 30))
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SatuSakuTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SatuSakuTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(SatuSakuTheme.border, lineWidth: 1)
        }
    }

    private func optionTapped(_ selection: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.48)) {
            mascotBounce.toggle()
            selection()
        }
    }

    private func advance() {
        viewModel.advance()
    }

    private func requestNotificationsAndContinue() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                notificationError = error.localizedDescription
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                advance()
            }
        }
    }
}

@MainActor
private struct SignalBarsView: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...4, id: \.self) { bar in
                Capsule()
                    .fill(bar <= level ? SatuSakuTheme.green : SatuSakuTheme.border)
                    .frame(width: 6, height: CGFloat(8 + bar * 5))
            }
        }
        .accessibilityLabel("\(level) out of 4 saving experience")
    }
}

#Preview {
    OnboardingContainerView(
        onCompleted: { _ in },
        onSignIn: {}
    )
}
