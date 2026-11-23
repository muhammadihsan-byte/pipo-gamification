import SwiftUI

@MainActor
struct ConsistencyMilestoneView: View {
    let xpEarned: Int
    let streakDays: Int
    let badgeTitles: [String]
    let isFirstSave: Bool
    let firstSparkEligible: Bool
    let onViewAchievements: () -> Void

    init(
        xpEarned: Int = GamificationManager.xpPerSaving,
        streakDays: Int,
        badgeTitles: [String] = [],
        isFirstSave: Bool = false,
        firstSparkEligible: Bool = false,
        onViewAchievements: @escaping () -> Void
    ) {
        self.xpEarned = xpEarned
        self.streakDays = streakDays
        self.badgeTitles = badgeTitles
        self.isFirstSave = isFirstSave
        self.firstSparkEligible = firstSparkEligible
        self.onViewAchievements = onViewAchievements
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Text(isFirstSave ? "Your first save!" : "That counts!\nNice work.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PipoTheme.ink)
                    .padding(.top, 54)

                Text(isFirstSave
                     ? "You recorded a saving for the first time. That's a real step."
                     : "Every step you take builds momentum.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PipoTheme.muted)

                if isFirstSave {
                    firstSaveReward.padding(.top, 4)
                    Text("That counts!")
                        .font(.subheadline.bold())
                        .foregroundStyle(PipoTheme.deepPink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(PipoTheme.palePink, in: Capsule())
                        .accessibilityIdentifier("pipo.firstSave.bubble")
                } else {
                    rewardSummary.padding(.top, 4)
                }

                Group {
                    if firstSparkEligible {
                        PipoFirstSparkScene()
                    } else {
                        PipoMascotView(companion: .celebration)
                    }
                }
                .frame(maxWidth: 340)
                .frame(height: 300)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Button("View my achievements", action: onViewAchievements)
                    .buttonStyle(PrimaryActionButtonStyle())
                Text("Your goal. Your pace. One step at a time.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PipoTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var firstSaveReward: some View {
        HStack(spacing: 16) {
            Image("PipoBadge_first-save")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("+\(xpEarned) XP")
                    .font(.title3.bold())
                    .foregroundStyle(PipoTheme.deepPink)
                Text("First Step unlocked")
                    .font(.subheadline.bold())
                    .foregroundStyle(PipoTheme.ink)
                    .accessibilityIdentifier("pipo.firstSave.badge")
                if badgeTitles.count > 1 {
                    Text("+\(badgeTitles.count - 1) more badges unlocked")
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var rewardSummary: some View {
        VStack(spacing: 8) {
            Label("+\(xpEarned) XP", systemImage: "sparkles")
                .foregroundStyle(PipoTheme.deepPink)
            if let latestBadge = badgeTitles.first {
                Label("Badge unlocked: \(latestBadge)", systemImage: "medal.fill")
                    .foregroundStyle(PipoTheme.pink)
                if badgeTitles.count > 1 {
                    Text("+\(badgeTitles.count - 1) more badges unlocked")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PipoTheme.muted)
                }
            } else {
                Label("Saving recorded", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(PipoTheme.pink)
            }
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(xpEarned) XP earned. " +
            (badgeTitles.isEmpty ? "Saving recorded." : "Badges unlocked: \(badgeTitles.joined(separator: ", "))."))
    }
}

// #72: Source-only native motion scaffold. Pipo V4 near-hoof/holding poses
// are NOT bundled yet; this renders the existing neutral still, allowing the
// approved Spark to approach without fabricating an anatomical frame.
// True pose-to-pose 780ms fidelity remains gated on the real exports and macOS QA.
@MainActor
private struct PipoFirstSparkScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = 0
    @State private var started = false

    private var visiblePhase: Int { reduceMotion ? 6 : phase }

    var body: some View {
        VStack(spacing: 7) {
            Text("FIRST SPARK")
                .font(.caption.bold())
                .foregroundStyle(PipoTheme.ink)
            Text("Your first saving period is recorded.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                Circle()
                    .fill(PipoTheme.palePink)
                    .frame(width: 224, height: 204)
                Image("PipoV4Neutral")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 185, height: 195)
                    .offset(y: visiblePhase == 4 ? -5 : 0)
                    .accessibilityHidden(true)
                PipoSparkIcon(state: .active, size: .spotlight)
                    .scaleEffect(visiblePhase == 3 ? 1.16 : 1.0)
                    .offset(
                        x: visiblePhase < 2 ? 96 : 64,
                        y: visiblePhase < 3 ? -21 : 26
                    )
                    .opacity(visiblePhase == 0 ? 0.65 : 1.0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 212)
            if reduceMotion {
                Text("No motion · same achievement")
                    .font(.caption2)
                    .foregroundStyle(PipoTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "First Spark. Your first saving period is recorded. " +
            "This is a saving recorded manually, not a verified bank transaction."
        )
        .accessibilityIdentifier("pipo.firstSpark.scene")
        .task { await playOnce() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                started = true
                self.phase = 6
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled {
                started = true
                phase = 6
            }
        }
    }

    private func playOnce() async {
        guard !started else { return }
        started = true
        guard !reduceMotion, scenePhase == .active else {
            phase = 6
            return
        }

        // Idle → Notice → Reach → Hug → Mini Jump → Settle; total 780ms.
        // We animate safe full-image transforms only until separate approved
        // anatomical artwork can be exported and verified in a native runner.
        let timeline: [(phase: Int, delayNanoseconds: UInt64, easing: Double)] = [
            (1, 0, 0.11),
            (2, 110_000_000, 0.13),
            (3, 130_000_000, 0.18),
            (4, 180_000_000, 0.20),
            (5, 200_000_000, 0.16),
            (6, 160_000_000, 0.10)
        ]
        for keyframe in timeline {
            if keyframe.delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: keyframe.delayNanoseconds)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, scenePhase == .active, !reduceMotion else {
                phase = 6
                return
            }
            withAnimation(.easeInOut(duration: keyframe.easing)) {
                phase = keyframe.phase
            }
        }
    }
}

#Preview {
    ConsistencyMilestoneView(streakDays: MockData.streakDays, onViewAchievements: {})
}
