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
                Card44Eyebrow(text: goal.isGroupGoal
                    ? "GROUP GOAL · DEVICE ONLY"
                    : "PERSONAL SAVING PLAN · " + goal.effectiveCurrencyCode)
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
                        let amountText = PipoGoalCurrency.display(
                            transaction.amount,
                            code: transaction.currencyCode ?? currencyForGoal(transaction.goalId),
                            exactMinor: transaction.amountMinorUnits
                        )
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
                            Text("+ " + amountText)
                                .font(.subheadline.bold())
                                .foregroundStyle(Card44.accent)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(titleForGoal(transaction.goalId)), saved \(amountText) on \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
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


// MARK: - Approved Journey & Achievements · Wave A (Ihsan Space section 10)
//
// This is a read-only projection of owner-scoped, persisted SwiftData entries.
// Do not award badges, mutate goal progress, infer Money Out or invent an
// earned-at timestamp while constructing a timeline. One real contribution
// appears once by stable event UUID, even when sync replays its local row.
enum PipoJourneyPeriod: String, CaseIterable, Identifiable {
    case month = "This month"
    case allTime = "All time"

    var id: String { rawValue }

    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .allTime: return true
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now) else {
                return false
            }
            return interval.contains(date)
        }
    }
}

struct PipoJourneyEntry: Identifiable {
    let transaction: SavingTransaction
    let goal: PersonalGoal
    var id: UUID { transaction.id }
    var currencyCode: String {
        transaction.currencyCode ?? goal.effectiveCurrencyCode
    }
    var amountText: String {
        PipoGoalCurrency.display(
            transaction.amount, code: currencyCode,
            exactMinor: transaction.amountMinorUnits
        )
    }
}

struct PipoJourneyMonthSection: Identifiable {
    let month: Date
    let entries: [PipoJourneyEntry]
    var id: Date { month }
}

enum PipoJourneyProjection {
    static func entries(
        goals: [PersonalGoal],
        transactions: [SavingTransaction],
        ownerID: UUID?,
        period: PipoJourneyPeriod = .allTime,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PipoJourneyEntry] {
        let owned = AccountScope.visibleGoals(goals, userID: ownerID)
        let rows = AccountScope.visibleTransactions(
            transactions, goals: owned, userID: ownerID
        )
        var byGoal: [UUID: PersonalGoal] = [:]
        for goal in owned where byGoal[goal.id] == nil {
            byGoal[goal.id] = goal
        }
        var seen = Set<UUID>()
        return rows.compactMap { row -> PipoJourneyEntry? in
            guard seen.insert(row.id).inserted,
                  period.contains(row.date, now: now, calendar: calendar),
                  let goal = byGoal[row.goalId] else { return nil }
            return PipoJourneyEntry(transaction: row, goal: goal)
        }
        .sorted {
            if $0.transaction.date != $1.transaction.date {
                return $0.transaction.date > $1.transaction.date
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Never combine unlike ISO currencies. If even one row is malformed
    /// or the exact sum overflows, suppress ALL money totals rather than
    /// silently displaying a partial or imprecise balance.
    static func exactTotals(_ entries: [PipoJourneyEntry]) -> [(code: String, minor: Int64)] {
        var byCurrency: [String: Int64] = [:]
        for entry in entries {
            let code = entry.currencyCode.uppercased()
            guard PipoGoalCurrency.isSupported(code),
                  let amount = entry.transaction.amountMinorUnits ??
                    PipoGoalCurrency.legacyMinor(entry.transaction.amount, code: code),
                  amount > 0 else { return [] }
            let (total, overflow) = byCurrency[code, default: 0]
                .addingReportingOverflow(amount)
            guard !overflow else { return [] }
            byCurrency[code] = total
        }
        return byCurrency.keys.sorted().compactMap { code in
            byCurrency[code].map { (code: code, minor: $0) }
        }
    }

    static func months(
        _ entries: [PipoJourneyEntry], calendar: Calendar
    ) -> [PipoJourneyMonthSection] {
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .month, for: entry.transaction.date)?.start ??
                calendar.startOfDay(for: entry.transaction.date)
        }
        return grouped.keys.sorted(by: >).map {
            PipoJourneyMonthSection(month: $0, entries: grouped[$0] ?? [])
        }
    }

    static func totalEarnedXP(_ entries: [PipoJourneyEntry]) -> Int? {
        var total = 0
        for entry in entries {
            guard entry.transaction.xpEarned >= 0 else { return nil }
            let (next, overflow) = total.addingReportingOverflow(
                entry.transaction.xpEarned
            )
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}

/// Approved Journey overview, full timeline, badges entry and true zero
/// states. The surrounding Dashboard still owns navigation, modelContext,
/// financial mutations and the existing achievement collection.
struct PipoJourneyWaveAView: View {
    let goals: [PersonalGoal]
    let transactions: [SavingTransaction]
    let ownerID: UUID?
    let earnedBadgeIDs: Set<String>
    let onCreateGoal: () -> Void
    let onOpenGoal: (PersonalGoal) -> Void
    let onOpenBadges: () -> Void
    let onOpenRecord: (SavingTransaction) -> Void

    @Environment(\.calendar) private var calendar
    @State private var showingFullTimeline = false
    @State private var selectedPeriod: PipoJourneyPeriod = .month

    private var ownedGoals: [PersonalGoal] {
        AccountScope.visibleGoals(goals, userID: ownerID)
    }

    private var allEntries: [PipoJourneyEntry] {
        PipoJourneyProjection.entries(
            goals: goals, transactions: transactions, ownerID: ownerID,
            period: .allTime, calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if showingFullTimeline {
                fullTimeline
            } else if ownedGoals.isEmpty {
                noGoalsState
            } else if allEntries.isEmpty {
                noRecordsState
            } else {
                journeyOverview
            }
        }
        .accessibilityIdentifier("pipo.journey.waveA")
        .onChange(of: ownerID) { _, _ in
            showingFullTimeline = false
            selectedPeriod = .month
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YOUR STORY")
                .font(.caption2.bold())
                .foregroundStyle(PipoTheme.deepPink)
                .tracking(0.7)
            Text(showingFullTimeline ? "Your timeline" : "Your journey")
                .font(.largeTitle.bold())
                .foregroundStyle(PipoTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pipo.journey.title")
            Text(showingFullTimeline ? "Every recorded step has a place." :
                 ownedGoals.isEmpty ? "Start with something meaningful." :
                 allEntries.isEmpty ? "Your goal is ready whenever you are." :
                 "Those little steps really count.")
                .font(.subheadline)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if showingFullTimeline {
                Button {
                    showingFullTimeline = false
                } label: {
                    Label("Back to your journey", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PipoTheme.deepPink)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("pipo.journey.back")
            }
        }
    }

    private var journeyOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            let monthly = PipoJourneyProjection.entries(
                goals: goals, transactions: transactions, ownerID: ownerID,
                period: .month, calendar: calendar
            )
            TicketCard(style: .approvedBlush) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(Date.now.formatted(.dateTime.month(.wide).year()).uppercased())
                            .foregroundStyle(PipoTheme.deepPink)
                        Spacer(minLength: 8)
                        Text("MANUAL LOGS")
                            .foregroundStyle(PipoTheme.muted)
                    }
                    .font(.caption2.bold())
                    HStack(alignment: .center, spacing: 15) {
                        Text("\(monthly.count)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(PipoTheme.ink)
                            .monospacedDigit()
                            .accessibilityIdentifier("pipo.journey.monthCount")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(monthly.count == 1 ? "save this month" : "saves this month")
                                .font(.headline.bold())
                                .foregroundStyle(PipoTheme.ink)
                            Text("Your recorded steps, at your own pace.")
                                .font(.caption)
                                .foregroundStyle(PipoTheme.muted)
                        }
                    }
                    let totals = PipoJourneyProjection.exactTotals(monthly)
                    if totals.count == 1, let first = totals.first {
                        HStack(alignment: .firstTextBaseline) {
                            Text("TOTAL RECORDED")
                                .font(.caption2.bold())
                                .foregroundStyle(PipoTheme.muted)
                            Spacer(minLength: 4)
                            Text(PipoGoalCurrency.formatted(first.minor, code: first.code))
                                .font(.headline.bold())
                                .foregroundStyle(PipoTheme.deepPink)
                                .minimumScaleFactor(0.75)
                                .lineLimit(1)
                                .accessibilityIdentifier("pipo.journey.monthTotal")
                        }
                    } else if totals.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RECORDED BY CURRENCY")
                                .font(.caption2.bold())
                                .foregroundStyle(PipoTheme.muted)
                            ForEach(totals, id: \.code) { item in
                                HStack {
                                    Text(item.code).foregroundStyle(PipoTheme.muted)
                                    Spacer()
                                    Text(PipoGoalCurrency.formatted(item.minor, code: item.code))
                                        .foregroundStyle(PipoTheme.deepPink)
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                        .accessibilityIdentifier("pipo.journey.multiCurrencyTotals")
                    } else {
                        Text("No single amount to total this month.")
                            .font(.caption)
                            .foregroundStyle(PipoTheme.muted)
                    }
                    Divider()
                    HStack {
                        if let xp = PipoJourneyProjection.totalEarnedXP(monthly) {
                            Text("\(xp) XP from recorded saves")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PipoTheme.ink)
                        }
                        Spacer(minLength: 4)
                        Button("View timeline") {
                            showingFullTimeline = true
                            selectedPeriod = .month
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PipoTheme.deepPink)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("pipo.journey.openTimeline")
                    }
                }
            }
            HStack {
                Text("Your timeline")
                    .font(.headline.bold())
                    .foregroundStyle(PipoTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all") {
                    showingFullTimeline = true
                    selectedPeriod = .allTime
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.deepPink)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pipo.journey.seeAll")
            }
            if allEntries.isEmpty {
                Text("Your recorded saves will appear here.")
                    .foregroundStyle(PipoTheme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(allEntries.prefix(2)) { entry in
                        entryRow(entry)
                    }
                }
            }
            badgeEntry
            Text("You recorded these savings. Pipo doesn't verify bank balances.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pipo.journey.manualDisclosure")
            footerNote("Every little step is part of your story.")
        }
    }

    private var fullTimeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ForEach(PipoJourneyPeriod.allCases) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period == .month
                             ? Date.now.formatted(.dateTime.month(.wide).year())
                             : period.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedPeriod == period
                                ? PipoTheme.deepPink : PipoTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                selectedPeriod == period
                                    ? PipoTheme.palePink : Color(.systemGray6),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                    .accessibilityIdentifier(
                        period == .month ? "pipo.journey.filter.month" :
                            "pipo.journey.filter.allTime"
                    )
                }
            }
            let entries = PipoJourneyProjection.entries(
                goals: goals, transactions: transactions, ownerID: ownerID,
                period: selectedPeriod, calendar: calendar
            )
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No saves in this period yet.")
                        .font(.headline)
                        .foregroundStyle(PipoTheme.ink)
                    Text("Any savings you've recorded in other months are still here.")
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                    if selectedPeriod == .month {
                        Button("View all time") {
                            selectedPeriod = .allTime
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 24)
                .accessibilityIdentifier("pipo.journey.periodEmpty")
            } else {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(PipoJourneyProjection.months(entries, calendar: calendar)) {
                        section in
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.month.formatted(.dateTime.month(.wide).year()).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(PipoTheme.muted)
                            Spacer(minLength: 6)
                            Text("\(section.entries.count) SAVES")
                                .font(.caption2.bold())
                                .foregroundStyle(PipoTheme.deepPink)
                        }
                        .padding(.top, 6)
                        ForEach(section.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            Text("These are manually recorded entries, not bank transactions.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pipo.journey.manualDisclosure")
        }
        .accessibilityIdentifier("pipo.journey.fullTimeline")
    }

    private func entryRow(_ entry: PipoJourneyEntry) -> some View {
        Button {
            onOpenRecord(entry.transaction)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus")
                    .font(.subheadline.bold())
                    .foregroundStyle(PipoTheme.deepPink)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.goal.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(PipoTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(entry.transaction.date.formatted(
                        .dateTime.day().month(.abbreviated).year()
                    ) + " · Saved manually")
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                }
                Spacer(minLength: 4)
                Text("+ " + entry.amountText)
                    .font(.subheadline.bold())
                    .foregroundStyle(PipoTheme.deepPink)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(entry.goal.title), saved \(entry.amountText), " +
            "\(entry.transaction.date.formatted(date: .abbreviated, time: .omitted))"
        )
        .accessibilityHint("Opens the saved entry detail")
        .accessibilityIdentifier("pipo.journey.record.\(entry.id.uuidString)")
    }

    private var badgeEntry: some View {
        Button(action: onOpenBadges) {
            HStack(spacing: 12) {
                Image("PipoBadge_first-save")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .opacity(earnedBadgeIDs.contains(PipoBadge.firstSave.rawValue) ? 1 : 0.4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("See your badges")
                        .font(.headline.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text(earnedBadgeIDs.isEmpty
                         ? "Your first badge is waiting."
                         : "\(earnedBadgeIDs.count) badges earned")
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(PipoTheme.deepPink)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pipo.journey.openAchievements")
    }

    private var noGoalsState: some View {
        VStack(alignment: .leading, spacing: 25) {
            invitationCard(
                eyebrow: "A NEW JOURNEY", headline: "Start small.",
                message: "Pick a goal that matters to you.",
                actionTitle: "Create your first goal", action: onCreateGoal
            )
            VStack(alignment: .leading, spacing: 16) {
                emptyStep("01", text: "Create a saving goal")
                emptyStep("02", text: "Record what you save elsewhere")
                emptyStep("03", text: "Watch progress and badges grow")
            }
            Button("Create a saving goal", action: onCreateGoal)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("pipo.journey.createGoal")
            Text("Pipo doesn't hold or transfer money. You remain in control.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
            footerNote("One goal at a time. Easy.")
        }
        .accessibilityIdentifier("pipo.journey.empty.noGoals")
    }

    private var noRecordsState: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let goal = ownedGoals.first {
                invitationCard(
                    eyebrow: "YOUR GOAL IS READY", headline: "Your first save.",
                    message: "You can record a saving whenever you're ready.",
                    actionTitle: "View \(goal.title)",
                    action: { onOpenGoal(goal) }
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SAVING GOAL")
                        .font(.caption2.bold())
                        .foregroundStyle(PipoTheme.deepPink)
                    Text(goal.title)
                        .font(.title2.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text(
                        PipoGoalCurrency.display(
                            goal.currentAmount, code: goal.effectiveCurrencyCode,
                            exactMinor: goal.exactRecordedMinor
                        ) + " recorded · Target " +
                        PipoGoalCurrency.display(
                            goal.targetAmount, code: goal.effectiveCurrencyCode,
                            exactMinor: goal.exactTargetMinor
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(PipoTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: goal.progress)
                        .tint(PipoTheme.deepPink)
                    Text("\(Int(goal.progress * 100))% complete · No saving entries recorded")
                        .font(.caption)
                        .foregroundStyle(PipoTheme.muted)
                    Button("View \(goal.title)") { onOpenGoal(goal) }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("pipo.journey.viewGoal")
                }
            }
            Text("No daily streak is required to start. Your goal stays here.")
                .font(.footnote)
                .foregroundStyle(PipoTheme.muted)
            footerNote("Start small. I'll be right here.")
        }
        .accessibilityIdentifier("pipo.journey.empty.noRecords")
    }

    private func invitationCard(
        eyebrow: String, headline: String, message: String,
        actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow)
                        .font(.caption2.bold())
                        .foregroundStyle(PipoTheme.deepPink)
                    Text(headline)
                        .font(.title2.bold())
                        .foregroundStyle(PipoTheme.ink)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(PipoTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 3)
                PipoV4HeadCrop()
                    .accessibilityHidden(true)
            }
            Button(actionTitle, action: action)
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.deepPink)
                .frame(minHeight: 44, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(PipoTheme.border, lineWidth: 1.5)
        )
    }

    private func emptyStep(_ number: String, text: String) -> some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.subheadline.bold())
                .foregroundStyle(PipoTheme.ink)
                .monospacedDigit()
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func footerNote(_ copy: String) -> some View {
        HStack(spacing: 10) {
            Text(copy)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PipoTheme.ink)
            Spacer(minLength: 3)
            PipoV4HeadCrop()
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(PipoTheme.palePink, in: RoundedRectangle(cornerRadius: 20))
    }
}
