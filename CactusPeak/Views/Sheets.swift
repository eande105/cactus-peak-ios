import SwiftUI

// MARK: - Sheet host (one sheet at a time)

struct SheetHost: View {
    let sheet: AppSheet
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        Group {
            switch sheet {
            case .pass: PassView()
            case .cancel(let id): CancelSheet(bookingID: id)
            case .waitlist(let id): WaitlistSheet(sessionID: id)
            case .clubSwitcher(let m): ClubSwitcherSheet(mode: m)
            case .hours(let id): HoursSheet(clubID: id)
            case .invite(let id): InviteSheet(sessionID: id)
            case .feedback(let id): FeedbackSheet(bookingID: id)
            case .reserve(let r): ReserveSheet(request: r)
            case .filters: FiltersSheet()
            case .datePicker: DatePickerSheet()
            case .guestShare: GuestShareSheet()
            case .addFamily: AddFamilySheet()
            case .comparePlans: ComparePlansSheet()
            case .planConfirm(let p): PlanConfirmSheet(plan: p)
            case .freezeConfirm(let m): FreezeConfirmSheet(months: m)
            case .ptPicker(let c): PTPickerSheet(coachID: c)
            case .editProfile: EditProfileSheet()
            case .calendar(let id): CalendarSheet(bookingID: id)
            case .goal: GoalSheet()
            case .page(let r): PageSheet(route: r)
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(dragIndicator)
        .presentationBackgroundInteraction(backgroundInteraction)
        .tint(Color.brandAccent)
    }

    private var detents: Set<PresentationDetent> {
        let large: Set<PresentationDetent> = [.large]
        let both: Set<PresentationDetent> = [.medium, .large]
        if dts.isAccessibilitySize { return large }
        switch sheet {
        case .pass, .addFamily, .comparePlans, .ptPicker, .editProfile, .calendar, .page: return large
        case .clubSwitcher, .filters: return both
        case .reserve(let r): return r.kind == .kidsClub ? large : both
        default: return both
        }
    }
    private var dragIndicator: Visibility {
        switch sheet { case .pass: .hidden; default: .visible }
    }
    private var backgroundInteraction: PresentationBackgroundInteraction {
        if case .reserve = sheet { return .enabled(upThrough: .medium) }
        return .automatic
    }
}

// MARK: - Cancel

struct CancelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let bookingID: BookingID
    @State private var reason: String?
    @State private var other = ""

    var body: some View {
        NavigationStack {
            if let b = model.booking(bookingID) {
                let p = model.cancelPreview(b)
                let alt = model.sameClassThisWeek(b)
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cancel \(b.title)?").font(.headline).accessibilityAddTraits(.isHeader)
                            Text("\(b.start.cpWeekdayShort) \(b.start.cpTimeShort)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        consequences(b, p)
                    }
                    Section {
                        Button("Keep my spot") { router.dismissSheet() }.primaryAction(full: true)
                    }
                    .listRowBackground(Color.clear)
                    Section {
                        if !alt.isEmpty, b.kind == .classSession {
                            Button("Reschedule instead") {
                                router.dismissSheet()
                                router.day = alt[0].start.startOfAZDay; router.segment = .classes
                                model.currentClubID = alt[0].clubID; router.selection = .book; router.paths[.book] = []
                            }
                        }
                        Button("Cancel booking", role: .destructive) { confirm(b, p) }
                    }
                    if !p.late { reasons }
                }
                .navigationTitle("Cancel booking")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { router.dismissSheet() } } }
            } else {
                ContentUnavailableView("Booking not found", systemImage: "ticket")
            }
        }
    }

    @ViewBuilder private func consequences(_ b: Booking, _ p: CancelPreview) -> some View {
        switch b.kind {
        case .kids: Text("Kids club has no late-cancel strikes.").font(.subheadline)
        case .pt:
            Text(p.late ? "Counts as a used session." : "Free until \(p.freeUntil.cpWeekdayShort) \(p.freeUntil.cpTimeShort) (24 hours before).").font(.subheadline)
        default:
            if !p.late { Text("You can rebook until it fills.").font(.subheadline) }
            else {
                if p.pausesBookings {
                    Label("This is your 3rd strike. New bookings pause for 3 days, until \(p.pauseEnds.cpWeekdayShort) \(p.pauseEnds.cpDayMonth).", systemImage: "xmark.circle.fill").font(.subheadline).foregroundStyle(Color.statusDanger)
                } else {
                    Label("Counts as a strike (\(p.strikeNumber) of 3 in 30 days)", systemImage: "xmark.circle.fill").font(.subheadline).foregroundStyle(Color.statusDanger)
                }
                if b.kind == .classSession { Label("Your spot goes to the next person on the waitlist", systemImage: "xmark.circle.fill").font(.subheadline).foregroundStyle(Color.statusDanger) }
                Text("3 strikes in 30 days pause new bookings for 3 days.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var reasons: some View {
        Section("Why are you cancelling?") {
            Picker("Reason", selection: $reason) {
                ForEach(["Schedule changed", "Feeling unwell", "Booked by mistake", "Other reason"], id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.inline).labelsHidden()
            if reason == "Other reason" { TextField("Tell us more (optional)", text: $other) }
        }
    }

    private func confirm(_ b: Booking, _ p: CancelPreview) {
        let result = model.cancel(b.id, reason: reason == "Other reason" ? other : reason)
        router.dismissSheet()
        if let r = result, r.late { model.showToast(r.countsStrike ? "Cancelled. That counts as a late cancel." : "Cancelled.") }
        // Remove the detail page for a booking that is gone.
    }
}

// MARK: - Waitlist

struct WaitlistSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let sessionID: SessionID
    @State private var agreed = false

    var body: some View {
        NavigationStack {
            if let s = model.session(sessionID) {
                // After the Apple Store checkout sheet: what you are joining leads, then one group of label and
                // value rows, then the one thing to agree to.
                Form {
                    Section {
                        SheetSummaryHeader(title: s.name,
                                           line: "\(s.start.cpFormat("EEE MMM d")) · \(s.start.cpTimeShort)–\(s.end.cpTimeShort) · \(s.room)") {
                            ClassGraphic(category: s.category, variant: .square)
                        }
                    }
                    if model.activeWaitlists >= 5 {
                        Section {
                            Banner(tone: .warning, text: "You are on 5 waitlists. Leave one to join another.", actionTitle: "See my waitlists") { router.dismissSheet(); router.push(.myBookings) }
                        }
                    } else {
                        Section {
                            LabeledContent("Your place", value: "\(ordinal(model.waitlistCount(s) + 1)) in line")
                            LabeledContent("Joins until", value: s.start.addingTimeInterval(-3600).cpTimeShort)
                            LabeledContent("If a spot opens", value: "30 min to confirm")
                        } footer: {
                            Text("We send a push when a spot opens. The waitlist closes 1 hour before class.")
                        }
                        Section {
                            Toggle("I understand late cancels count as strikes", isOn: $agreed)
                            if !model.notificationsAuthorized { Label("Alerts are off. Turn them on so you do not miss a spot.", systemImage: "bell.slash").font(.footnote).foregroundStyle(.secondary) }
                        } footer: { Text("Turn this on to join.") }
                        Section { Button("Pick another class") { router.dismissSheet() }.linkAction() }
                    }
                }
                .listSectionSpacing(.compact)
                .navigationTitle("Join waitlist").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Join") {
                            if let b = model.joinWaitlist(s) {
                                Task { _ = await NotificationSupport.shared.requestAuthorization() }
                                router.dismissSheet(); model.announceBooked(b)
                            }
                        }.disabled(!agreed || model.activeWaitlists >= 5).fontWeight(.semibold)
                    }
                }
            }
        }
    }
    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .ordinal; return f.string(from: NSNumber(value: n)) ?? "\(n)th"
    }
}

// MARK: - Reserve (courts, lanes, kids club)

struct ReserveSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let request: ReserveRequest
    @State private var court = 0           // 0 = any
    @State private var lane = 0
    @State private var chosenKids: Set<PersonID> = []
    @State private var note = ""
    @State private var error: String?
    @State private var reserved = false

    private var club: Club { model.club(request.clubID) }
    /// Court length comes from `router.duration`, set before the sheet opens. The sheet has no second control for it.
    private var req: ReserveRequest { request }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SheetSummaryHeader(title: headerTitle, line: headerLine) {
                        SpaceGraphic(id: headerSpace).padding(9).frame(width: 56, height: 56)
                            .background(Color.surfaceMuted).clipShape(CutTileShape())
                    }
                }
                Section { holdBanner }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                switch request.kind {
                case .court: courtBody
                case .lane: laneBody
                case .kidsClub: kidsBody
                }
                if let error {
                    Section { Label(error, systemImage: "xmark.circle.fill").font(.subheadline).foregroundStyle(Color.statusDanger) }
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle(request.kind == .court ? "Reserve court" : (request.kind == .lane ? "Reserve lane" : "Kids club"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reserve") { submit() }.accessibilityLabel(reserveTitle).fontWeight(.semibold).disabled(request.kind == .kidsClub && chosenKids.isEmpty)
                }
            }
        }
        .onAppear { reserved = false; model.beginHold(req, label: summary) }
        .onDisappear { if !reserved { model.endHold() } }
    }

    private var summary: String {
        switch request.kind {
        case .court: "\(request.sport?.title ?? "Court") · \(request.start.cpFormat("EEE MMM d")) · \(club.fullName)"
        case .lane: "Lap swim · \(request.start.cpFormat("EEE MMM d")), \(request.start.cpTimeShort) · \(club.fullName)"
        case .kidsClub: "\(club.fullName) · \(request.start.cpFormat("EEE MMM d")), \(request.start.cpTimeShort)–\(request.start.addingTimeInterval(7200).cpTimeShort)"
        }
    }

    private var headerTitle: String {
        switch request.kind {
        case .court: request.sport?.title ?? "Court"
        case .lane: "Lap swim"
        case .kidsClub: "Kids club"
        }
    }
    private var headerLine: String {
        let day = request.start.cpFormat("EEE MMM d")
        let end = request.start.addingTimeInterval(Double(request.kind == .kidsClub ? 120 : (request.kind == .lane ? 45 : request.duration)) * 60)
        return "\(day) · \(request.start.cpTimeShort)–\(end.cpTimeShort) · \(club.fullName)"
    }
    private var headerSpace: SpaceGraphicID {
        switch request.kind { case .court: .courts; case .lane: .lapPool; case .kidsClub: .kidsClub }
    }

    // Hold banner: 5 minutes, one extension
    @ViewBuilder private var holdBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let h = model.hold, h.expires > model.now {
                let secs = Int(h.expires.timeIntervalSince(model.now))
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label("Holding \(holdName) for \(secs / 60):\(String(format: "%02d", secs % 60))", systemImage: "timer").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Spacer()
                        if !h.extended { Button("Add 5 minutes") { model.extendHold() }.linkAction().font(.subheadline) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Holding \(holdName) for \(secs / 60):\(String(format: "%02d", secs % 60))", systemImage: "timer").font(.subheadline.weight(.semibold)).monospacedDigit()
                        if !h.extended { Button("Add 5 minutes") { model.extendHold() }.linkAction().font(.subheadline) }
                    }
                }
                .padding(12).background(Color.statusWarningSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if !reserved {
                // Only a real expiry shows this. A successful reserve clears the hold too, and must not look like a failure.
                Banner(tone: .danger, text: "Your hold ended. Pick the time again.", actionTitle: "Hold again") { model.beginHold(req, label: summary) }
            }
        }
        .sensoryFeedback(.error, trigger: model.holdExpiredCount)
    }
    private var holdName: String {
        switch request.kind {
        case .court: court == 0 ? "a court" : "Court \(court)"
        case .lane: lane == 0 ? "a lane" : "Lane \(lane)"
        case .kidsClub: "this block"
        }
    }

    // Courts
    @ViewBuilder private var courtBody: some View {
        let sport = request.sport ?? .pickleball
        let slot = model.courtSlots(club: club, sport: sport, day: request.start.startOfAZDay, duration: request.duration).first { $0.start == request.start }
        Section {
            LabeledContent("Length", value: "\(request.duration) min")
            LabeledContent("Included with", value: model.member.plan.name)
        }
        Section {
            ChoiceList(selection: $court, options: [(0, "Any court", nil)] + (1...max(club.courts(for: sport), 1)).map { c in
                (c, "Court \(c)", (slot?.free.contains(c) ?? false) ? nil : "Taken") })
        } header: { Text("Court") } footer: {
            Text("Add a partner after you reserve. Free cancel until \(request.start.addingTimeInterval(-7200).cpTimeShort). Later is a late cancel.")
        }
    }

    @ViewBuilder private var laneBody: some View {
        let slot = model.laneSlots(club: club, day: request.start.startOfAZDay).first { $0.start == request.start }
        Section { LabeledContent("Length", value: "45 min") }
        Section {
            ChoiceList(selection: $lane, options: [(0, "Any lane", nil)] + (1...max(club.lanes, 1)).map { l in
                let sw = slot?.swimmers[l - 1] ?? 2
                return (l, "Lane \(l)", sw == 1 ? "1 of 2 swimmers" : (sw >= 2 ? "Full" : nil)) })
        } header: { Text("Lane") } footer: {
            Text("Free cancel until \(request.start.addingTimeInterval(-7200).cpTimeShort).")
        }
    }

    @ViewBuilder private var kidsBody: some View {
        let blk = model.kidsBlocks(club: club, day: request.start.startOfAZDay).first { $0.index == request.block }
        if let blk {
            Section { LabeledContent("Spots") { CapacityIndicator(left: blk.spotsLeft, capacity: blk.capacity, noun: "spots") } }
        }
        Section("Children") {
            ForEach(model.kidsEligible) { c in
                Button { if chosenKids.contains(c.id) { chosenKids.remove(c.id) } else { chosenKids.insert(c.id) } } label: {
                    HStack {
                        Text("\(c.first), \(c.age)").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: chosenKids.contains(c.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosenKids.contains(c.id) ? Color.accentColor : Color.secondary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(chosenKids.contains(c.id) ? .isSelected : [])
            }
            if model.kidsEligible.isEmpty { Text("No children aged 6 months to 12 years on your plan.").font(.subheadline).foregroundStyle(.secondary) }
        }
        Section {
            TextField("Allergies or notes (140 characters)", text: $note, axis: .vertical)
                .onChange(of: note) { _, n in if n.count > 140 { note = String(n.prefix(140)) } }
        } footer: {
            Text("Up to 2 blocks per child a day. Check in at \(club.fullName) by \(request.start.addingTimeInterval(15 * 60).cpTimeShort) or we release the block. Kids club has no strikes.")
        }
    }

    private var kidsFull: Bool {
        let blk = model.kidsBlocks(club: club, day: request.start.startOfAZDay).first { $0.index == request.block }
        return request.kind == .kidsClub && (blk?.spotsLeft ?? 1) == 0
    }

    private var reserveTitle: String {
        switch request.kind {
        case .court: court == 0 ? "Reserve court" : "Reserve Court \(court)"
        case .lane: lane == 0 ? "Reserve lane" : "Reserve Lane \(lane)"
        case .kidsClub: kidsFull ? "Join waitlist" : (chosenKids.isEmpty ? "Reserve spots" : "Reserve \(chosenKids.count) spot\(chosenKids.count == 1 ? "" : "s")")
        }
    }

    private func submit() {
        error = nil
        let result: ReserveResult
        switch request.kind {
        case .court: result = model.reserveCourt(req, court: court == 0 ? nil : court)
        case .lane: result = model.reserveLane(req, lane: lane == 0 ? nil : lane)
        case .kidsClub:
            let kids = model.kidsEligible.filter { chosenKids.contains($0.id) }
            if kidsFull { if let b = model.joinKidsWaitlist(req, children: kids) { reserved = true; router.dismissSheet(); model.announceBooked(model.booking(b.id)) }; return }
            result = model.reserveKids(req, children: kids, note: note)
        }
        switch result {
        case .ok(let b): reserved = true; router.dismissSheet(); model.announceBooked(model.booking(b.id))
        case .failed(let m): error = m
        }
    }
}

// MARK: - Club switcher

struct ClubSwitcherSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let mode: SwitcherMode
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(clubs) { c in
                    let reason = disabledReason(c)
                    Button { select(c) } label: {
                        ClubCard(club: c, reading: model.busyness(c), now: model.now, variant: .listRow,
                                 isHome: c.id == model.member.homeClubID, selected: isSelected(c))
                    }
                    .buttonStyle(.plain).disabled(reason != nil)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Club or city")
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } }
            }
        }
    }

    private var title: String {
        switch mode { case .pass: "Check in at"; case .viewing: "Club" }
    }
    private var clubs: [Club] {
        model.clubs.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) || $0.zip.contains(query) }
    }
    private func isSelected(_ c: Club) -> Bool {
        model.currentClubID == c.id
    }
    private func disabledReason(_ c: Club) -> String? {
        nil
    }
    private func select(_ c: Club) {
        model.currentClubID = c.id
        if c.courts(for: router.sport) == 0, let sp = c.courtSports.first { router.sport = sp }
        router.dismissSheet()
    }
}

// MARK: - Hours

struct HoursSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    let clubID: ClubID
    var body: some View {
        let club = model.club(clubID)
        NavigationStack {
            List {
                Section("Hours") { HoursTable(club: club, now: model.now) }
                Section {
                    Text("6 am–8 pm").monospacedDigit()
                } header: { Text("Desk staffed") } footer: { Text("Door readers work whenever the club is open.") }
                if club.hasKids {
                    Section("Kids club") {
                        Text("Mon–Sat 8–10 am, 10 am–12 pm, 4–6 pm, 6–8 pm")
                        Text("Ages 6 months to 12 years.").foregroundStyle(.secondary)
                    }
                }
                if club.hasPool { Section("Pool") { Text("Closes 30 minutes before the club.") } }
                Section("Holiday hours") { Text("Thanksgiving, Nov 26: 6 am–2 pm") }
                Section { Button { openURL(URL(string: "tel:\(club.phone.filter(\.isNumber))")!) } label: { Label("Call the club · \(club.phone)", systemImage: "phone") } }
            }
            .navigationTitle(club.fullName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}

// MARK: - Invite a friend

struct InviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let sessionID: SessionID
    @State private var copied = false
    var body: some View {
        let link = "https://app.cactuspeak.example/invite/class/\(sessionID.suffix(24))"
        NavigationStack {
            Form {
                if let s = model.session(sessionID) { Section { Text("Invite a friend to \(s.name)").font(.headline) } }
                Section {
                    Text(link).codeFont(.footnote, weight: .regular).textSelection(.enabled)
                    Button { UIPasteboard.general.string = link; copied = true } label: { Label(copied ? "Copied" : "Copy link", systemImage: "doc.on.doc") }
                    ShareLink(item: link) { Label("Share", systemImage: "square.and.arrow.up") }
                } footer: { Text("Guest passes left this month: \(model.guestPassesLeft)") }
            }
            .navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}

// MARK: - Private feedback

struct FeedbackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let bookingID: BookingID
    @State private var choice: String?
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                if let b = model.booking(bookingID) { Section { Text("How was \(b.title)?").font(.headline) } }
                Section {
                    Picker("Answer", selection: $choice) {
                        ForEach(["Great", "Okay", "Not for me"], id: \.self) { Text($0).tag(Optional($0)) }
                    }.pickerStyle(.inline).labelsHidden()
                }
                Section { TextField("Add a note (optional)", text: $note, axis: .vertical) } footer: { Text("Only the club sees this.") }
            }
            .navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { model.giveFeedback(bookingID, choice ?? "Okay"); router.dismissSheet(); model.showToast("Thanks. Only the club sees this.") }.disabled(choice == nil)
                }
            }
        }
    }
}

/// Single-choice rows with a checkmark, for use inside a `Section`. Disabled rows say why.
struct ChoiceList: View {
    @Binding var selection: Int
    var options: [(Int, String, String?)]
    var body: some View {
        ForEach(options, id: \.0) { o in
            let off = o.2 == "Taken" || o.2 == "Full"
            Button { selection = o.0 } label: {
                HStack {
                    Text(o.1).foregroundStyle(off ? Color.secondary : Color.primary)
                    if let n = o.2 { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    Spacer()
                    if selection == o.0 { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(off)
            .accessibilityAddTraits(selection == o.0 ? .isSelected : [])
        }
    }
}


/// The top of a booking sheet: the item's art tile, its name and one line of when and where. After the Apple Store
/// checkout sheet, where the item leads and the facts follow in one group.
struct SheetSummaryHeader<Art: View>: View {
    var title: String
    var line: String
    @ViewBuilder var art: Art
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                              : AnyLayout(HStackLayout(spacing: 14))
        layout {
            art.frame(width: 56, height: 56).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(line).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
