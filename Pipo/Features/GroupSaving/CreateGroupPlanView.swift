import ImageIO
import PhotosUI
import SwiftUI

@MainActor
struct CreateGroupPlanView: View {
    let onBack: () -> Void
    let onDashboard: () -> Void

    @State private var draft = GroupPlanDraft()
    @State private var editBaseline: GroupPlanDraft?
    @State private var navigation = GroupPlanNavigation()
    @State private var categoryOpen = false
    @State private var memberInput = ""
    @State private var memberError: String?
    @State private var photoLoading = false
    @FocusState private var nameFocused: Bool
    @State private var touchedName = false
    @Environment(AuthStateManager.self) private var auth

    var body: some View {
        Group {
            if navigation.step == .review, let review = draft.review(creatorID: auth.userID) {
                ReviewGroupSavingView(review: review, onBack: back, onEdit: edit, onCreate: { navigation.didSave() })
            } else {
                SavingPlanPage(flowTitle: "Group saving plan", stepNumber: navigation.step.rawValue,
                               count: 7, stepTitle: navigation.step.title, ready: navigation.step == .success,
                               onBack: back) {
                    fields
                } footer: {
                    actions
                }
                .onChange(of: nameFocused) { was, focused in
                    if was && !focused { touchedName = true }
                }
            }
        }
        .pipoPageTransition(value: navigation.step.rawValue)
    }

    @ViewBuilder private var fields: some View {
        switch navigation.step {
        case .goal: goal
        case .target: target
        case .timeline: timeline
        case .rules: rules
        case .setup: setup
        case .invitations: invitations
        case .success: success
        case .review: EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        if navigation.step == .success {
            Button("Open dashboard", action: onDashboard).buttonStyle(PersonalPlanPrimaryStyle())
        } else {
            VStack(spacing: 4) {
                PersonalPlanActions(back: back, showsBack: navigation.step != .goal,
                                    title: navigation.step == .invitations ? "Review Group" : "Continue",
                                    dimmed: !draft.valid(navigation.step) || photoLoading,
                                    action: { advance(skipping: false) })
                if navigation.step == .invitations {
                    Button { advance(skipping: true) } label: {
                        Text("Invite later").font(.subheadline.bold()).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func back() {
        nameFocused = false
        if navigation.step == .success { onDashboard() }
        else if navigation.editing, let editBaseline {
            if !draft.valid(.review) { draft = editBaseline }
            navigation.back(draft)
            self.editBaseline = nil
        }
        else if navigation.step == .goal { onBack() }
        else { navigation.back(draft) }
    }

    private func advance(skipping: Bool) {
        nameFocused = false
        if navigation.step == .invitations {
            if !skipping && !memberInput.trimmed.isEmpty && !addMember() { return }
            draft.inviteLater = skipping
        }
        navigation.advance(draft)
    }

    private func edit(_ section: GroupReviewSection) {
        let step: GroupPlanStep = switch section {
        case .goal: .goal
        case .target: .target
        case .timeline: .timeline
        case .contributionRules: .rules
        case .squad: .setup
        case .members: .invitations
        }
        editBaseline = draft
        navigation.edit(step)
    }

    private var goal: some View {
        Group {
            PersonalPlanIntro(step: .goal, title: "What are you saving for?",
                              subtitle: "Hi, I’m Pipo! Let’s give your next goal a little direction.")
            VStack(alignment: .leading, spacing: 6) {
                PersonalPlanFieldLabel(title: "Goal name", status: "Required")
                TextField("Give your goal a name", text: $draft.title)
                    .focused($nameFocused).accessibilityLabel("Goal name")
                    .onSubmit { nameFocused = false }
                    .personalPlanField(invalid: touchedName && draft.title.trimmed.isEmpty)
                if touchedName && draft.title.trimmed.isEmpty { feedback("Enter a goal name to continue.") }
                hint("Your saving purpose can be different from your group name.")
            }
            VStack(alignment: .leading, spacing: 6) {
                PersonalPlanFieldLabel(title: "Goal category", status: "Required")
                Button {
                    nameFocused = false // Dismiss the keyboard before revealing category options.
                    categoryOpen.toggle()
                } label: {
                    HStack {
                        Text(draft.category?.rawValue ?? "Choose a category")
                        Spacer()
                        Image(systemName: categoryOpen ? "chevron.up" : "chevron.down")
                    }.personalPlanField()
                }.buttonStyle(.plain).accessibilityLabel("Goal category").accessibilityValue(draft.categoryTitle)
                if categoryOpen {
                    ForEach(GroupPlanCategory.allCases, id: \.self) { category in
                        PersonalPlanChoice(title: category.rawValue, selected: draft.category == category) {
                            draft.category = category
                            categoryOpen = false
                        }
                        .accessibilityIdentifier("pipo.qa.group.category.\(category.rawValue)")
                    }
                }
                if draft.category == .other {
                    field("Custom category", "Enter your category", $draft.customCategory)
                    if draft.customCategory.trimmed.isEmpty { feedback("Enter your custom category to continue.") }
                } else if draft.category == nil && touchedName { feedback("Choose a category to continue.") }
            }
            PlanPhotoPicker(title: "Add goal image", data: $draft.goalPhoto, loading: $photoLoading)
            field("Short description", "What makes this goal special?", $draft.goalDescription, optional: true)
            PersonalPlanNote(title: "A goal that’s yours, together", message: "Choose something meaningful to your group.")
        }.font(.subheadline)
    }

    private var target: some View {
        Group {
            GroupStepIntro("How much do we need together?", "Set a shared target for \(draft.title.trimmed).")
            if draft.usesBreakdown {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared target · calculated from items").font(.caption.bold())
                    Text(draft.target.map { money($0) } ?? "Complete your breakdown").font(.title2.bold())
                    hint("The items add up to your shared target.")
                }.groupPlanCard()
            } else {
                PersonalPlanFieldLabel(title: "Target amount (Rp)", status: "Required")
                RupiahInput(label: "Shared target in rupiah", text: $draft.targetText)
                if !draft.targetText.isEmpty && draft.target == nil { feedback("Enter a positive whole amount in rupiah.") }
            }
            Toggle(isOn: $draft.usesBreakdown) {
                VStack(alignment: .leading) {
                    Text("Enable target breakdown").font(.subheadline.bold())
                    hint("Optional · plan with individual items")
                }
            }.frame(minHeight: 44)
            if draft.usesBreakdown {
                ForEach($draft.items) { $item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("Item name", text: $item.title).personalPlanField()
                            RupiahInput(label: "Amount for \(item.cleanTitle.isEmpty ? "item" : item.cleanTitle)", text: $item.amount)
                            Button { draft.items.removeAll { $0.id == item.id } } label: {
                                Image(systemName: "minus.circle").frame(width: 44, height: 44)
                            }.accessibilityLabel("Remove \(item.cleanTitle.isEmpty ? "item" : item.cleanTitle)")
                        }
                        if item.cleanTitle.isEmpty || item.rupiah == nil { feedback("Each item needs a name and a positive amount.") }
                    }
                }
                Button { draft.items.append(GoalBreakdownDraft()) } label: {
                    Label("Add row", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
                PersonalPlanNote(title: draft.target.map { "Breakdown total · \(money($0))" } ?? "Finish every item to continue",
                                 message: "Pipo calculates the shared target once every item is valid.",
                                 background: PersonalPlanStyle.mint, accent: PersonalPlanStyle.green)
            } else {
                PersonalPlanNote(title: "One target is enough", message: "You can continue with a single total.")
            }
        }.font(.subheadline)
    }

    private var timeline: some View {
        Group {
            GroupStepIntro("When do we want to reach our goal?", "Choose a date to aim for, together.")
            Text("Choose one · Required")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
            PersonalPlanChoice(title: draft.usesDuration ? "Target date" : "Target date · selected",
                               selected: !draft.usesDuration) { draft.usesDuration = false }
            if !draft.usesDuration {
                SavingDateEditor(entry: $draft.dateEntry, start: draft.start, calendar: draft.calendar)
            }
            PersonalPlanChoice(title: draft.usesDuration ? "Duration · selected" : "Duration",
                               selected: draft.usesDuration) { draft.usesDuration = true }
            if draft.usesDuration {
                Picker("Months from plan start", selection: $draft.months) {
                    ForEach(1...36, id: \.self) { value in Text("\(value) \(value == 1 ? "month" : "months")").tag(value) }
                }.personalPlanField()
            }
            if let end = draft.end {
                let contributionDetail = draft.schedule.map {
                    " That gives \($0.count) planned contribution dates."
                } ?? ""
                PersonalPlanNote(title: "Plan starts · \(dateLabel(draft.start))",
                                 message: "Aiming for \(dateLabel(end)).\(contributionDetail)")
            } else { feedback("Choose a date after the plan starts.") }
            Text("Your target date is an intention, not a guaranteed finish. You can adjust it as your group’s plans change.")
                .font(.caption)
                .foregroundStyle(PersonalPlanStyle.muted)
        }
    }

    private var rules: some View {
        Group {
            GroupStepIntro("How do we want to contribute?", "Choose a plan that works for your group.")
            ForEach(GroupContributionMode.allCases, id: \.self) { mode in
                PersonalPlanChoice(title: mode.rawValue, selected: draft.mode == mode) { draft.mode = mode }
            }
            VStack(alignment: .leading, spacing: 6) {
                PersonalPlanFieldLabel(title: "Expected contributors", status: "Required")
                TextField("Including you", text: $draft.expected).keyboardType(.numberPad)
                    .accessibilityLabel("Expected contributors").personalPlanField(invalid: draft.contributors == nil)
                if draft.contributors == nil { feedback("Enter a positive whole number, including you.") }
                hint("Used for planning. Members join separately.")
            }
            if draft.mode == .flexible {
                PersonalPlanNote(title: "Your pace, your amount",
                                 message: "Members record what they save, when they can. No fixed amount is required.")
                LabeledContent("Shared target", value: draft.target.map { money($0) } ?? "")
                if let end = draft.end { LabeledContent("Aiming for", value: dateLabel(end)) }
            }
            Text(draft.mode == .equal ? "Contribution rhythm · Required" : "Group check-in rhythm · Optional")
                .font(.caption.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach([SavingRhythm.daily, .weekly, .biWeekly, .monthly]) { rhythm in
                    PersonalPlanChoice(title: rhythm.title,
                                       selected: draft.mode == .equal ? draft.rhythm == rhythm : draft.checkIn == rhythm) {
                        if draft.mode == .equal { draft.rhythm = rhythm }
                        else { draft.checkIn = draft.checkIn == rhythm ? nil : rhythm }
                    }
                }
            }
            if draft.mode == .equal {
                if draft.rhythm == .monthly {
                    SavingDayGrid(title: "Preferred contribution date", days: Array(1...31),
                                  selection: $draft.monthDay, label: { String($0) })
                } else if draft.rhythm == .weekly || draft.rhythm == .biWeekly {
                    SavingDayGrid(title: "Preferred contribution day", days: [2, 3, 4, 5, 6, 7, 1],
                                  selection: $draft.weekday, label: { draft.calendar.shortWeekdaySymbols[$0 - 1] })
                }
                if let estimate = draft.estimate, let schedule = draft.schedule, let target = draft.target, let people = draft.contributors {
                    PersonalPlanNote(title: "\(money(estimate))\(draft.rhythm.unitLabel) per expected member",
                                     message: "\(money(target)) across \(schedule.count) periods and \(people) expected contributors, rounded up to whole rupiah. The final contribution may be smaller.")
                } else if draft.schedule == nil {
                    feedback("Choose a saving day or timeline with at least one contribution date.")
                }
            } else {
                hint("Check-ins are optional. There is no scheduled completion estimate.")
                if let target = draft.target {
                    let fraction = (150_000.0 / Double(target)).formatted(.percent.precision(.fractionLength(1)))
                    PersonalPlanNote(title: "Example only · Rp100.000 + Rp50.000", message: "Rp150.000 would be \(fraction) of your target. Your group starts at Rp0.")
                }
            }
        }.font(.subheadline)
    }

    private var setup: some View {
        Group {
            GroupStepIntro("Let’s set up our group.", "Give your saving team its own identity.")
            PersonalPlanNote(title: "Saving for \(draft.title.trimmed)", message: draft.categoryTitle,
                             background: PersonalPlanStyle.surface, accent: PersonalPlanStyle.ink)
            field("Group name", "Give your group a name", $draft.groupName)
            PlanPhotoPicker(title: "Add group photo", data: $draft.groupPhoto, loading: $photoLoading)
            field("Group description", "Tell your team about this group", $draft.groupDescription, optional: true)
            PersonalPlanNote(title: "Private · Invite-only", message: "Fixed group setting. This plan is stored on this device.",
                             background: PersonalPlanStyle.surface, accent: PersonalPlanStyle.ink)
            Label("You — Group Admin", systemImage: "person").font(.subheadline.bold())
        }
    }

    private var invitations: some View {
        Group {
            GroupStepIntro("Who’s joining your saving journey?", "You can create your group before anyone else joins.")
            VStack(alignment: .leading, spacing: 10) {
                Text("\(draft.groupName.trimmed) · Private").font(.headline)
                Label("You · Group Admin", systemImage: "person")
                LabeledContent("Current members", value: "1 (you)")
                LabeledContent("Expected contributors", value: "\(draft.contributors ?? 1) · planning only")
            }.groupPlanCard()
            VStack(alignment: .leading, spacing: 8) {
                PersonalPlanFieldLabel(title: "Prepare a member invitation", status: "Optional")
                TextField("Name or @handle", text: $memberInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().personalPlanField()
                    .onChange(of: memberInput) { _, _ in memberError = nil }
                if let memberError { feedback(memberError) }
                Button { _ = addMember() } label: { Text("Add to list").frame(minHeight: 44) }
                    .disabled(memberInput.trimmed.isEmpty)
                ForEach(draft.preparedMembers, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Text("Unsent").foregroundStyle(PersonalPlanStyle.muted)
                        Button { draft.preparedMembers.removeAll { $0 == name } } label: {
                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("Remove \(name)")
                    }
                }
            }.groupPlanCard()
            VStack(alignment: .leading, spacing: 8) {
                Text("Private invite link").font(.caption.bold())
                Label("Link unavailable", systemImage: "link")
                    .foregroundStyle(PersonalPlanStyle.muted).personalPlanField()
                hint("Link sharing is unavailable for this local plan.")
            }.groupPlanCard()
            PersonalPlanNote(title: "0 invitations sent", message: "Names stay on this device. Invite links and delivery are unavailable.")
        }.font(.subheadline)
    }

    private func addMember() -> Bool {
        do {
            try draft.prepareMember(memberInput)
            memberInput = ""
            memberError = nil
            return true
        } catch {
            memberError = error.localizedDescription
            return false
        }
    }

    private var success: some View {
        Group {
            GroupStepIntro("Your saving team is ready!", "One small step, together.")
            PipoMascotView(companion: .celebration).frame(height: 108).frame(maxWidth: .infinity).accessibilityHidden(true)
            Label {
                Text("\(draft.groupName.trimmed) saved on this device")
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.headline).foregroundStyle(PersonalPlanStyle.green)
            .pipoEntrance()
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.title.trimmed).font(.headline)
                if let target = draft.target { LabeledContent("Shared target", value: money(target)) }
                LabeledContent("Recorded contributions", value: "Rp0 · 0%")
                ProgressView(value: 0.0)
            }.groupPlanCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Your team starts with you").font(.headline)
                LabeledContent("Joined members", value: "1 (you)")
                LabeledContent("Invitations sent", value: "0")
                LabeledContent("Expected contributors", value: "\(draft.contributors ?? 1) · planning only")
            }.groupPlanCard()
        }
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>, optional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonalPlanFieldLabel(title: title, status: optional ? "Optional" : "Required")
            TextField(prompt, text: text, axis: optional ? .vertical : .horizontal)
                .lineLimit(optional ? 2...4 : 1...1)
                .accessibilityLabel(title).font(.subheadline).personalPlanField()
        }
    }
    private func feedback(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(PersonalPlanStyle.error)
    }
    private func hint(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(PersonalPlanStyle.muted)
    }
}

struct GroupStepIntro: View {
    let title: String
    let subtitle: String
    init(_ title: String, _ subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.footnote).foregroundStyle(PersonalPlanStyle.muted)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

extension View {
    func groupPlanCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(PersonalPlanStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PlanPhotoPreview: View {
    let data: Data?
    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 140).accessibilityLabel("Selected photo")
        }
    }
}

private struct PlanPhotoPicker: View {
    let title: String
    @Binding var data: Data?
    @Binding var loading: Bool
    @State private var selection: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlanPhotoPreview(data: data)
            let photoLabel = data == nil ? title : "Change photo"
            PhotosPicker(selection: $selection, matching: .images) {
                PlanPhotoPickerLabel(photoLabel)
            }
            if data != nil {
                Button { selection = nil; data = nil } label: { Text("Remove photo").frame(minHeight: 44) }
            }
            if loading { ProgressView("Loading photo…") }
            if let error { Text(error).font(.caption).foregroundStyle(PersonalPlanStyle.error) }
        }
        .task(id: selection) {
            guard let selection else { loading = false; return }
            loading = true
            error = nil
            do {
                guard let bytes = try await selection.loadTransferable(type: Data.self),
                      let scaled = await Self.thumbnail(bytes) else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                data = scaled
            } catch {
                if !Task.isCancelled { self.error = "Couldn’t load this photo. Choose another image." }
            }
            if !Task.isCancelled { loading = false }
        }
        .onDisappear { loading = false }
    }

    private nonisolated static func thumbnail(_ bytes: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1024,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}

private struct PlanPhotoPickerLabel: View {
    let title: String

    nonisolated init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label(title, systemImage: "photo.badge.plus").personalPlanField()
    }
}
