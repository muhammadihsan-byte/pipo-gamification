import SwiftUI

@MainActor
struct ConsistencyMilestoneView: View {
    let xpEarned: Int
    let streakDays: Int
    let badgeTitles: [String]
    let isFirstSave: Bool
    let onViewAchievements: () -> Void

    init(
        xpEarned: Int = GamificationManager.xpPerSaving,
        streakDays: Int,
        badgeTitles: [String] = [],
        isFirstSave: Bool = false,
        onViewAchievements: @escaping () -> Void
    ) {
        self.xpEarned = xpEarned
        self.streakDays = streakDays
        self.badgeTitles = badgeTitles
        self.isFirstSave = isFirstSave
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

                PipoMascotView(companion: .celebration)
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

#Preview {
    ConsistencyMilestoneView(streakDays: MockData.streakDays, onViewAchievements: {})
}
