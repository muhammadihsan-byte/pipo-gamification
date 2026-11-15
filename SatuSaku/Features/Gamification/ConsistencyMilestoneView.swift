import SwiftUI

@MainActor
struct ConsistencyMilestoneView: View {
    let xpEarned: Int
    let streakDays: Int
    let onViewAchievements: () -> Void

    init(
        xpEarned: Int = GamificationManager.xpPerSaving,
        streakDays: Int,
        onViewAchievements: @escaping () -> Void
    ) {
        self.xpEarned = xpEarned
        self.streakDays = streakDays
        self.onViewAchievements = onViewAchievements
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Text("Consistency looks good\non you!")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SatuSakuTheme.ink)
                    .padding(.top, 54)

                Text("Every step you take builds momentum.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SatuSakuTheme.muted)

                rewardSummary
                    .padding(.top, 4)

                PipoMascotView(state: .celebrating)
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
                    .foregroundStyle(SatuSakuTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var rewardSummary: some View {
        VStack(spacing: 8) {
            Label("+\(xpEarned) XP", systemImage: "sparkles")
                .foregroundStyle(SatuSakuTheme.deepPink)
            Label("\(streakDays)-day streak", systemImage: "flame.fill")
                .foregroundStyle(SatuSakuTheme.pink)
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SatuSakuTheme.palePink, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(xpEarned) XP earned. You are on a \(streakDays)-day streak.")
    }
}

#Preview {
    ConsistencyMilestoneView(streakDays: MockData.streakDays, onViewAchievements: {})
}
