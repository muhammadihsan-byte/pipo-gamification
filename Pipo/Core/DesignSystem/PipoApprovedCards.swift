import Foundation
import SwiftUI
import UIKit

// #44: Each card is the selected Figma variant, not an experimental alternative.
// The shared TicketCard remains the only surface/container used by these cards.
// Every displayed amount comes from the caller's model or an explicitly
// non-persisted draft; no card awards XP, changes balances or syncs data.
private enum Card44 {
    static let ink = PipoTheme.cardInk
    static let muted = PipoTheme.cardMuted
    static let accent = PipoTheme.cardAccentReadable
    static let pink = Color(red: 255 / 255, green: 101 / 255, blue: 132 / 255)
    static let blush = Color(red: 255 / 255, green: 241 / 255, blue: 244 / 255)
}

private struct Card44Eyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(Card44.accent)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The exact approved V4 neutral image already bundled with Pipo. A cropped
/// still is preferred for cards; animation belongs to contextual scenes only.
struct PipoV4HeadCrop: View {
    var body: some View {
        Image("PipoV4Neutral")
            .resizable()
            .scaledToFit()
            .frame(width: 88, height: 97)
            .offset(y: 17)
            .frame(width: 72, height: 62, alignment: .top)
            .clipped()
            .background(Card44.blush, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Pipo")
    }
}

// 01 / Goal Focus B: never substitute the Figma Bali example photo for an
// actual goalPhoto. A no-photo state is truthful and has a useful identity.
struct PipoGoalFocusBCard: View {
    let goal: PersonalGoal

    var body: some View {
        TicketCard(style: .approvedCompact) {
            VStack(alignment: .leading, spacing: 10) {
                if let data = goal.goalPhoto, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Your photo for " + goal.title)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundStyle(Card44.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Card44Eyebrow(text: "YOUR GOAL")
                            Text(goal.categoryTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Card44.muted)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Card44.blush, in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.title)
                        .font(.title3.bold())
                        .foregroundStyle(Card44.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text("\(Int(goal.progress * 100))% logged")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Card44.accent)
                }
                ProgressView(value: goal.progress)
                    .tint(Card44.pink)
                    .accessibilityLabel("Goal progress")
                    .accessibilityValue("\(Int(goal.progress * 100)) percent")
                Text("A goal worth saving for · " + money(goal.currentAmount, goal: goal) +
                     " of " + money(goal.targetAmount, goal: goal) + " recorded")
                    .font(.caption)
                    .foregroundStyle(Card44.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pipo.card.goalFocusB")
    }
}

// 02 / Goal Progress B: the badge belongs to an account, not demonstrably to
// this exact goal. It is only visible after a persisted earned award and never
// creates a second goal progress rail.
struct PipoGoalProgressBCard: View {
    let quarterWayEarned: Bool
    let onOpenCollection: () -> Void

    var body: some View {
        Group {
            if quarterWayEarned {
                TicketCard(style: .approvedBlush) {
                    HStack(alignment: .center, spacing: 12) {
                        Image("PipoBadge_quarter-way")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 78)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Card44Eyebrow(text: "YOUR MILESTONE · EARNED")
                            Text("Quarter Way")
                                .font(.title3.bold())
                                .foregroundStyle(Card44.ink)
                            Text("You've earned this badge on your saving journey.")
                                .font(.caption)
                                .foregroundStyle(Card44.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("View achievements", action: onOpenCollection)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Card44.accent)
                                .frame(minHeight: 44, alignment: .leading)
                                .accessibilityIdentifier("pipo.card.progress.openCollection")
                        }
                    }
                }
                .accessibilityIdentifier("pipo.card.goalProgressB")
            }
        }
    }
}

// 05 / Milestones D. Art is the actual existing approved badge artwork;
// earned versus locked state is sourced only from UserProfile.
struct PipoMilestonesDCard: View {
    let earnedIDs: Set<String>
    let onOpenCollection: () -> Void

    private let featured: [PipoBadge] = [.firstSave, .quarterWay]

    var body: some View {
        TicketCard(style: .approvedBlush) {
            VStack(alignment: .leading, spacing: 12) {
                Card44Eyebrow(text: "YOUR STICKER ALBUM")
                HStack(alignment: .top, spacing: 12) {
                    ForEach(featured) { badge in
                        let isEarned = earnedIDs.contains(badge.rawValue)
                        VStack(spacing: 5) {
                            Image("PipoBadge_\(badge.rawValue)")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 86)
                                .opacity(isEarned ? 1 : 0.32)
                                .accessibilityHidden(true)
                            Text(badge.title)
                                .font(.caption.bold())
                                .foregroundStyle(Card44.ink)
                            Text(isEarned ? "Earned" : "Locked")
                                .font(.caption2)
                                .foregroundStyle(Card44.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(badge.title), \(isEarned ? "earned" : "locked")")
                    }
                }
                Text("Every badge marks a real saving milestone.")
                    .font(.footnote)
                    .foregroundStyle(Card44.muted)
                Button("Open your collection", action: onOpenCollection)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Card44.accent)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("pipo.dashboard.journey.achievements")
            }
        }
        .accessibilityIdentifier("pipo.card.milestonesD")
    }
}

// 06 / Inspiration C: private photo only, no static destination example.
struct PipoInspirationCCard: View {
    let goal: PersonalGoal

    var body: some View {
        TicketCard(style: .approvedMist) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Card44Eyebrow(text: "POSTCARD TO FUTURE ME")
                    Text(goal.title)
                        .font(.title3.bold())
                        .foregroundStyle(Card44.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Every little save counts.")
                        .font(.subheadline)
                        .foregroundStyle(Card44.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let data = goal.goalPhoto, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 108, height: 123)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Private goal photo")
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(Card44.muted)
                        .frame(width: 108, height: 123)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("No photo added for this goal")
                }
            }
            Text(goal.goalPhoto == nil ? "Your goal · Add a photo in a future update" :
                 "Your photo · Stored locally on this device")
                .font(.caption)
                .foregroundStyle(Card44.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("pipo.card.inspirationC")
    }
}

// 07 / Plan Overview B: group prepared names are *not* accepted members or
// synced records. Personal plans never show member names.
struct PipoPlanOverviewBCard: View {
    let goal: PersonalGoal
    var preparedMembers: [String] = []

    var body: some View {
        TicketCard(style: .approvedCompact) {
            VStack(alignment: .leading, spacing: 10) {
                Card44Eyebrow(text: goal.isGroupGoal ? "GROUP GOAL · DEVICE ONLY" : "PERSONAL SAVING PLAN")
                Text(goal.title)
                    .font(.title2.bold())
                    .foregroundStyle(Card44.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 14) {
                    stat(label: "TARGET", value: money(goal.targetAmount, goal: goal))
                    stat(label: "RECORDED", value: money(goal.currentAmount, goal: goal))
                }
                ProgressView(value: goal.progress)
                    .tint(Card44.pink)
                    .accessibilityLabel("Recorded progress")
                    .accessibilityValue("\(Int(goal.progress * 100)) percent")

                if goal.isGroupGoal {
                    if !preparedMembers.isEmpty {
                        Text("Prepared names (not invited): " + preparedMembers.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Card44.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(Int(goal.progress * 100))% manually recorded · Not live-synced")
                        .font(.caption)
                        .foregroundStyle(Card44.muted)
                } else {
                    Text("\(Int(goal.progress * 100))% recorded by you · Not a bank balance")
                        .font(.caption)
                        .foregroundStyle(Card44.muted)
                }
            }
        }
        .accessibilityIdentifier("pipo.card.planOverviewB")
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Card44Eyebrow(text: label)
            Text(value).font(.headline).foregroundStyle(Card44.ink)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 09 / Saving Decisions D — a *draft* route selector, NOT a bank action.
// This view stays in the protected QA showcase until #42 has a persisted
// account-scoped event ledger and tested schedule revisions.
enum PipoSavingRoute: String, CaseIterable, Sendable {
    case keepDate
    case keepAmount

    var label: String {
        switch self {
        case .keepDate: "Keep the date"
        case .keepAmount: "Keep the planned amount"
        }
    }
}

struct PipoSavingDecisionsDCard: View {
    @Binding var selection: PipoSavingRoute
    let suggestedAmount: Double?
    let laterDate: Date?

    var body: some View {
        TicketCard(style: .approvedBlush) {
            VStack(alignment: .leading, spacing: 8) {
                Card44Eyebrow(text: "TWO WAYS FORWARD / YOU CHOOSE")
                routeButton(.keepDate, detail: suggestedAmount.map {
                    "Estimated \(money($0)) each period"
                } ?? "Requires a valid plan schedule")
                routeButton(.keepAmount, detail: laterDate.map {
                    "Estimated completion \($0.formatted(date: .abbreviated, time: .omitted))"
                } ?? "Requires a valid plan schedule")
                Text("These are estimates, not promises. Nothing is changed yet.")
                    .font(.footnote)
                    .foregroundStyle(Card44.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pipo.card.savingDecisionsD")
    }

    private func routeButton(_ route: PipoSavingRoute, detail: String) -> some View {
        Button {
            selection = route
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == route ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Card44.accent)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.label)
                        .font(.subheadline.bold())
                        .foregroundStyle(Card44.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Card44.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == route ? .isSelected : [])
        .accessibilityIdentifier(route == .keepDate
                                 ? "pipo.card.decision.keepDate"
                                 : "pipo.card.decision.keepAmount")
    }
}

// 10 / Input & Editing D — interactive, uncommitted, never a real cash move.
// Persisting the draft is deliberately left to the authorized #42 flow.
enum PipoMoneyOutPreview {
    static func amount(from input: String, available: Double) -> Double? {
        guard let parsed = PersonalPlanFormatting.parseRupiah(input),
              parsed > 0, available.isFinite, available >= 0,
              Double(parsed) <= available else { return nil }
        return Double(parsed)
    }

    static func impact(before: Double, used: Double) -> Double? {
        guard before.isFinite, used.isFinite, before >= 0,
              used > 0, used <= before else { return nil }
        return before - used
    }
}

struct PipoInputEditingDCard: View {
    @Binding var amount: String
    @Binding var note: String
    let available: Double
    let onReview: () -> Void

    var body: some View {
        TicketCard(style: .approvedMist) {
            VStack(alignment: .leading, spacing: 10) {
                Card44Eyebrow(text: "YOUR RECORD / EDITABLE NOTE")
                VStack(alignment: .leading, spacing: 5) {
                    Text("MONEY USED ELSEWHERE")
                        .font(.caption.bold())
                        .foregroundStyle(Card44.muted)
                    TextField("Amount in IDR", text: $amount)
                        .accessibilityLabel("Amount in IDR")
                        .keyboardType(.numberPad)
                        .font(.title2.bold())
                        .foregroundStyle(Card44.ink)
                        .accessibilityIdentifier("pipo.card.moneyOut.amount")
                    Text("Recorded amount is a draft until confirmed in a future update.")
                        .font(.caption)
                        .foregroundStyle(Card44.muted)
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                TextField("Optional note", text: $note)
                    .textInputAutocapitalization(.sentences)
                    .font(.subheadline)
                    .accessibilityIdentifier("pipo.card.moneyOut.note")
                Text("No bank money moves when you enter this amount.")
                    .font(.footnote)
                    .foregroundStyle(Card44.muted)
                Button("Review this entry", action: onReview)
                    .font(.subheadline.bold())
                    .foregroundStyle(Card44.accent)
                    .frame(minHeight: 44)
                    .disabled(PipoMoneyOutPreview.amount(from: amount, available: available) == nil)
                    .accessibilityIdentifier("pipo.card.moneyOut.review")
            }
        }
        // Keep the card discoverable without collapsing its editable fields
        // into a single parent accessibility element on the iOS Simulator.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pipo.card.inputEditingD")
    }
}

// 11 / Financial Impact D — pure preview, with zero XP mutation.
struct PipoFinancialImpactDCard: View {
    let before: Double
    let amountUsed: Double
    let xpEarnedSoFar: Int

    var body: some View {
        TicketCard(style: .approvedBlush) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    PipoV4HeadCrop()
                    Card44Eyebrow(text: "A CHANGE, NOT A RESET")
                }
                if let after = PipoMoneyOutPreview.impact(before: before, used: amountUsed) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        stat("BEFORE", money(before))
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Card44.accent)
                            .accessibilityHidden(true)
                        stat("PREVIEW", money(after))
                    }
                    Text("\(money(amountUsed)) used elsewhere · Draft only")
                        .font(.caption)
                        .foregroundStyle(Card44.muted)
                } else {
                    Text("Enter a valid amount no greater than what you've recorded.")
                        .font(.subheadline)
                        .foregroundStyle(Card44.muted)
                }
                Text("Earlier saves and \(xpEarnedSoFar) XP still count. No changes saved.")
                    .font(.footnote)
                    .foregroundStyle(Card44.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pipo.card.financialImpactD")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Card44Eyebrow(text: label)
            Text(value)
                .font(.headline)
                .foregroundStyle(Card44.ink)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 12 / Activity & History D — only genuine, account-scoped saving events.
// No "money used" events exist until #42 provides a safe ledger.
struct PipoActivityHistoryDCard: View {
    let transactions: [SavingTransaction]
    let titleForGoal: (UUID) -> String
    var currencyForGoal: (UUID) -> String = { _ in "IDR" }

    var body: some View {
        TicketCard(style: .approvedBlush) {
            VStack(alignment: .leading, spacing: 10) {
                Card44Eyebrow(text: "MY SAVING JOURNAL")
                if transactions.isEmpty {
                    Text("No contributions recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(Card44.muted)
                } else {
                    ForEach(transactions.prefix(12)) { transaction in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 2) {
                                Text(transaction.date.formatted(.dateTime.day()))
                                    .font(.headline.bold())
                                Text(transaction.date.formatted(.dateTime.month(.abbreviated)))
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(Card44.accent)
                            .frame(width: 37)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(titleForGoal(transaction.goalId))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Card44.ink)
                                Text("Manually saved")
                                    .font(.caption)
                                    .foregroundStyle(Card44.muted)
                            }
                            Spacer(minLength: 0)
                            Text("+ " + PipoGoalCurrency.display(transaction.amount,
                                        code: transaction.currencyCode ?? currencyForGoal(transaction.goalId),
                                        exactMinor: transaction.amountMinorUnits))
                                .font(.subheadline.bold())
                                .foregroundStyle(Card44.accent)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(titleForGoal(transaction.goalId)), saved \(PipoGoalCurrency.display(transaction.amount,
                                        code: transaction.currencyCode ?? currencyForGoal(transaction.goalId),
                                        exactMinor: transaction.amountMinorUnits)) on \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                Text("Your own entries, not bank-verified transactions.")
                    .font(.footnote)
                    .foregroundStyle(Card44.muted)
            }
        }
        .accessibilityIdentifier("pipo.card.activityHistoryD")
    }
}

// 13 / Completion B — only goals *actually* reaching their target.
struct PipoCompletionBCard: View {
    let goal: PersonalGoal
    let onSeeJourney: () -> Void

    var body: some View {
        Group {
            if goal.lifecycleState == .completed {
                TicketCard(style: .approvedBlush) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Card44Eyebrow(text: "A GOAL YOU REACHED")
                            Text("You made it!")
                                .font(.title2.bold())
                                .foregroundStyle(Card44.ink)
                            Text(goal.title + " is complete.")
                                .font(.subheadline)
                                .foregroundStyle(Card44.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(money(goal.currentAmount, goal: goal) + " recorded / 100%")
                                .font(.caption)
                                .foregroundStyle(Card44.muted)
                            Button("See your journey", action: onSeeJourney)
                                .font(.subheadline.bold())
                                .foregroundStyle(Card44.accent)
                                .frame(minHeight: 44, alignment: .leading)
                                .accessibilityIdentifier("pipo.card.completion.seeJourney")
                        }
                        Spacer(minLength: 0)
                        Image("PipoV4Joy")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 106, maxHeight: 135)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("pipo.card.completionB")
            }
        }
    }
}

// 13E / Empty B — the selected first-time state, with approved V4 artwork.
struct PipoEmptyStateBCard: View {
    let onCreate: () -> Void

    var body: some View {
        TicketCard(style: .approvedBlush) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    Card44Eyebrow(text: "A NEW JOURNEY")
                    Text("Start small.")
                        .font(.title2.bold())
                        .foregroundStyle(Card44.ink)
                    Text("Pick a goal that matters to you.")
                        .font(.subheadline)
                        .foregroundStyle(Card44.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PipoV4HeadCrop()
            }
            Button("Create a saving goal", action: onCreate)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("pipo.card.empty.create")
        }
        .accessibilityIdentifier("pipo.card.emptyStateB")
    }
}

// The last three cards are preview-only until #42 supplies real local events.
// This gallery is never routed from a production screen and cannot mutate
// accounts, goal progress, transactions or XP.
#if DEBUG
struct PipoMoneyOutCardsQAShowcase: View {
    @State private var amount = "500000"
    @State private var note = ""
    @State private var route = PipoSavingRoute.keepDate
    @State private var reviewed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("Design-only money-out previews")
                    .font(.headline)
                Text("No saving history or bank balance will be changed here.")
                    .font(.subheadline)
                PipoInputEditingDCard(
                    amount: $amount, note: $note, available: 1_500_000,
                    onReview: { reviewed = true }
                )
                if reviewed {
                    PipoFinancialImpactDCard(
                        before: 1_500_000,
                        amountUsed: PipoMoneyOutPreview.amount(from: amount, available: 1_500_000) ?? 0,
                        xpEarnedSoFar: 600
                    )
                    PipoSavingDecisionsDCard(
                        selection: $route,
                        suggestedAmount: 250_000,
                        laterDate: Calendar.current.date(byAdding: .month, value: 2, to: .now)
                    )
                }
        }
        .padding(.vertical, 6)
    }
}
#endif


#if DEBUG
/// Read-only design/interaction fixture for a single remote iOS QA run.
/// Simulates a completion solely inside this DEBUG preview; main app data,
/// App Store build, account records and awards are never changed.
struct PipoApprovedCardsGalleryQA: View {
    let goal: PersonalGoal
    let groupGoal: PersonalGoal?
    let transactions: [SavingTransaction]
    let earnedIDs: Set<String>
    let onOpenCollection: () -> Void
    let onCreateGoal: () -> Void
    let onSeeJourney: () -> Void

    private var completedExample: PersonalGoal {
        PersonalGoal(
            title: "Completed demo goal", category: .trip,
            targetAmount: 1000, currentAmount: 1000,
            targetDate: .now, ownerUserID: goal.ownerUserID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("APPROVED PIPO CARDS · QA ONLY")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            PipoGoalFocusBCard(goal: goal)
            PipoGoalProgressBCard(
                quarterWayEarned: earnedIDs.contains(PipoBadge.quarterWay.rawValue),
                onOpenCollection: onOpenCollection
            )
            PipoMilestonesDCard(earnedIDs: earnedIDs, onOpenCollection: onOpenCollection)
            PipoInspirationCCard(goal: goal)
            PipoPlanOverviewBCard(goal: groupGoal ?? goal)

            PipoMoneyOutCardsQAShowcase()

            PipoActivityHistoryDCard(
                transactions: transactions,
                titleForGoal: { _ in goal.title }
            )
            PipoCompletionBCard(goal: completedExample, onSeeJourney: onSeeJourney)
            PipoEmptyStateBCard(onCreate: onCreateGoal)
        }
        .accessibilityIdentifier("pipo.cards.allQa")
    }
}
#endif
