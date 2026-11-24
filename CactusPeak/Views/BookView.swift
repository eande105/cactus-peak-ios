import SwiftUI

struct BookView: View {
    /// Toolbar buttons zoom the sheets they open out of themselves (see `zoomSource`).
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    @State private var showCalendar = false

    var body: some View {
        Group {
            switch router.segment {
            case .classes: ClassesList()
            case .courts: ReserveList(kind: .court)
            case .lanes: ReserveList(kind: .lane)
            case .kids: ReserveList(kind: .kidsClub)
            }
        }
        // The header is a bar under the toolbar, so the list scrolls under it and the bar's hard edge effect covers
        // both. At accessibility sizes it scrolls with the list instead (see BookHeaderSection).
        .safeAreaBar(edge: .top, spacing: 0) { if !dts.isAccessibilitySize { BookHeader() } }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle("Book")
        .navigationBarTitleDisplayMode(.inline)
        // The club button stands in for the title. The title stays set for VoiceOver and the back button.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ClubMenuButton() }
            // The calendar is a circle button in the bar, as in Apple Fitness, not a cell in the day strip.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCalendar = true } label: { Image(systemName: "calendar") }
                    .barItem()
                    .accessibilityLabel("Pick a date")
                    .popover(isPresented: $showCalendar) { BookCalendarPopover() }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.present(.page(.myBookings), zoomFrom: "book.bookings") } label: { Label("Bookings", systemImage: "ticket") }
                    .labelStyle(.iconOnly).barItem()
            }
            .zoomSource("book.bookings", in: zoomNamespace)
        }
    }

    private var club: Club { model.club(model.currentClubID) }
}

/// Segment picker and day strip. The crowd for the day is the first section under it (DayCrowdSection). Pinned on iPhone at normal sizes, inside the list at accessibility sizes.
struct BookHeader: View {
    /// The list's own side margin, so the header's edges line up with the cards under it. The day strip and the chip
    /// row use it for their scroll content margins, which take a length. It equals the system's default padding on
    /// iPhone; views that can pad instead use `.padding(.horizontal)`, which follows the system.
    static let margin: CGFloat = 16
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 8) {
            // The days first, full width, as in Apple Fitness; then the option chips, as in Apple Maps Directions.
            if dts.isAccessibilitySize {
                Picker("Day", selection: $router.day) {
                    ForEach(days, id: \.self) { Text($0.cpFormat("EEEE, MMM d")).tag($0) }
                }.pickerStyle(.menu)
            } else {
                ScheduleDayStrip(days: days, selected: Binding(get: { router.day }, set: { router.day = $0 }),
                                 counts: { dayCount($0) }, dimmed: { dayDimmed($0) }, booked: { hasBooking($0) },
                                 onCalendar: nil)
            }
            BookControlBar()
        }
        .padding(.bottom, dts.isAccessibilitySize ? 0 : 6)
    }

    private var days: [Date] {
        switch router.segment {
        case .classes, .lanes, .kids: model.reserveDays(.kidsClub)
        case .courts: model.reserveDays(.court)
        }
    }
    private func dayCount(_ d: Date) -> Int? {
        guard router.segment == .classes, router.filters.activeCount > 0 else { return nil }
        return model.sessions(club: model.currentClubID, day: d).count
    }
    private func hasBooking(_ d: Date) -> Bool {
        model.bookings.contains { $0.status == .booked && AZ.cal.isDate($0.start, inSameDayAs: d) }
    }
    private func dayDimmed(_ d: Date) -> Bool {
        let kind: ReserveKind = router.segment == .courts ? .court : .kidsClub
        return model.reserveOpensAt(d, kind: kind) > model.now
    }
}

struct BookHeaderSection: View {
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        if dts.isAccessibilitySize { Section { BookHeader() }.listRowBackground(Color.clear) }
    }
}

// MARK: - Classes

struct ClassesList: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    @State private var loading = true
    @Environment(\.colorScheme) private var scheme

    private var clubIDs: [ClubID] { [model.currentClubID] }

    private var sessions: [ClassSession] {
        let f = router.filters
        return clubIDs.flatMap { model.sessions(club: $0, day: router.day) }.filter { s in
            (f.categories.isEmpty || f.categories.contains(s.category))
            && (f.times.isEmpty || f.times.contains(TimeOfDay.of(s.start)))
            && s.intensity <= f.maxIntensity
            && (f.coachID == nil || s.coachID == f.coachID)
            && (!f.firstTimers || s.firstTimers)
            && (!f.spotsOnly || model.spotsLeft(s) > 0)
            && (!f.myBookings || model.booking(forSession: s.id) != nil)
        }.sorted { ($0.start <= model.now ? 1 : 0, $0.start) < ($1.start <= model.now ? 1 : 0, $1.start) }
    }

    var body: some View {
        let list = sessions
        let sections = Dictionary(grouping: list, by: { TimeOfDay.of($0.start) })
        List {
            BookHeaderSection()
            if router.filters.activeCount > 0 { Section { filterChips } }
            Section {
                if let r = model.bookingBlock, r != .offline { Banner(tone: .warning, text: "\(r.label). \(r.note)", actionTitle: nil, action: nil) }
                if model.offline { OfflineBanner(text: model.savedDataText) }
            }
            // Banners are cards themselves: no row background, and their edges meet the list's side margin.
            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))

            DayCrowdSection(day: router.day)
            ClassExploreSections()

            ForEach(TimeOfDay.allCases) { tod in
                if let items = sections[tod], !items.isEmpty {
                    Section {
                        ForEach(items.sorted { ($0.start <= model.now ? 1 : 0, $0.start) < ($1.start <= model.now ? 1 : 0, $1.start) }) { s in
                            let d = model.rowData(s)
                            NavigationLink(value: AppRoute.classSession(s.id)) {
                                ClassRow(data: d, showClub: clubIDs.count > 1, onAction: { ClassActions.primary(s, model: model, router: router) },
                                         onLeave: { if let b = model.booking(forSession: s.id) { model.leaveWaitlist(b.id) } })
                            }
                            .navigationLinkIndicatorVisibility(.hidden)
                            .swipeActions(edge: .trailing) { rowActions(s, d) }
                            .contextMenu { rowActions(s, d) }
                            .accessibilityAction(named: "Book") { ClassActions.primary(s, model: model, router: router) }
                        }
                    } header: { DetailSectionHeader(title: tod.rawValue, detail: items.count == 1 ? "1 class" : "\(items.count) classes") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        // The pinned day strip sits right above the first card.
        .contentMargins(.top, 8, for: .scrollContent)
        .redacted(reason: loading ? .placeholder : [])
        .task { try? await Task.sleep(for: .milliseconds(350)); loading = false }
        .overlay {
            if model.forceError {
                EmptyState(title: "Can't load classes", message: "Check your connection, then try again.", symbol: "wifi.exclamationmark", actionTitle: "Try again") { model.forceError = false }
                    .background(Color(.systemGroupedBackground))
            } else if list.isEmpty && !loading {
                EmptyState(title: "No classes \(router.day.cpFormat("EEE d"))",
                           message: "\(clubIDs.count == 1 ? model.club(clubIDs[0]).fullName : "These clubs") has no classes that match. Try \(nextDayWithClasses.map { $0.cpFormat("EEE d") } ?? "another day").",
                           symbol: "calendar.badge.exclamationmark",
                           actionTitle: nextDayWithClasses.map { "Go to \($0.cpFormat("EEE d"))" },
                           action: { if let d = nextDayWithClasses { router.day = d } },
                           secondaryTitle: router.filters.activeCount > 0 ? "Clear filters" : nil,
                           secondary: { router.filters = ScheduleFilters() })
                .background(Color(.systemGroupedBackground))
            }
        }
        .refreshable { try? await Task.sleep(for: .milliseconds(500)) }
    }

    /// Same actions for the swipe and the context menu. One place decides which ones fit the row's state.
    @ViewBuilder private func rowActions(_ s: ClassSession, _ d: ClassRowData) -> some View {
        switch d.state {
        case .book, .dropIn:
            Button("Book", systemImage: "checkmark.circle") { ClassActions.primary(s, model: model, router: router) }.tint(Color.brandAccent)
        case .waitlist:
            Button("Join waitlist", systemImage: "clock") { ClassActions.primary(s, model: model, router: router) }.tint(Color.brandSecondary)
        case .hold:
            Button("Confirm spot", systemImage: "bell.badge") { ClassActions.primary(s, model: model, router: router) }.tint(Color.brandAccent)
        case .booked:
            if let b = model.booking(forSession: s.id) {
                Button("Cancel booking", systemImage: "xmark.circle", role: .destructive) { router.requestCancel(b.id) }
            }
        case .waitlisted:
            if let b = model.booking(forSession: s.id) {
                Button("Leave waitlist", systemImage: "xmark.circle", role: .destructive) { model.leaveWaitlist(b.id) }
            }
        default:
            EmptyView()
        }
    }

    private var nextDayWithClasses: Date? {
        (1...6).map { router.day.addingDays($0) }.first { d in clubIDs.contains { !model.sessions(club: $0, day: d).isEmpty } && d <= model.lastBookableDay }
    }

    /// Filters live in the toolbar sheet. Active ones show as one summary row with a clear button.
    @ViewBuilder private var filterChips: some View {
        if router.filters.activeCount > 0 {
            HStack {
                Label("\(router.filters.activeCount) filter\(router.filters.activeCount == 1 ? "" : "s") on", systemImage: "line.3.horizontal.decrease")
                Spacer()
                Button("Clear") { router.filters = ScheduleFilters() }.linkAction()
            }
        }
    }
}

// MARK: - Courts, lanes and kids club

struct ReserveList: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    let kind: ReserveKind

    private var club: Club { model.club(model.currentClubID) }
    private var plan: PlanTier { model.member.plan }

    var body: some View {
        @Bindable var router = router
        let day = router.day
        let opens = model.reserveOpensAt(day, kind: kind)
        List {
            BookHeaderSection()
            DayCrowdSection(day: day)
            // A block banner when one applies; the rules go in the footer. The controls are chips in the header.
            Section {
                if let r = model.bookingBlock, kind != .kidsClub, r != .offline { Banner(tone: .warning, text: "\(r.label). \(r.note)", actionTitle: nil, action: nil) }
            } footer: { Text(rule + " Times are Arizona time.") }
            // The banner is a card itself: no row background, and its edges meet the list's side margin.
            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(.init(top: 2, leading: 0, bottom: 2, trailing: 0))

            if let blocker = restriction {
                Section { blocker }.listRowBackground(Color.clear)
            } else if opens > model.now {
                Section {
                    Text("\(kind.title) for \(day.cpFormat("EEE MMM d")) open \(opens.cpWeekdayShort) at \(opens.cpTimeShort)").font(.subheadline)
                    if kind == .court { Text("Courts can be booked 3 days ahead.").font(.footnote).foregroundStyle(.secondary) }
                }
            } else {
                switch kind {
                case .court: courtRows(day)
                case .lane: laneRows(day)
                case .kidsClub: kidsRows(day)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        // The pinned day strip sits right above the first card.
        .contentMargins(.top, 8, for: .scrollContent)
    }

    // MARK: Controls
    private var rule: String {
        switch kind {
        case .court: "60 or 90 minutes. Book up to 3 days ahead. 1 court a day, 2 active at most. Included with Ridge and Summit."
        case .lane: "45-minute slots. Pool closes 30 minutes before the club. Up to 2 swimmers share a lane."
        case .kidsClub: "Ages 6 months to 12 years. 2-hour blocks. Up to 2 blocks per child a day. You check in at the same club."
        }
    }

    // MARK: Restrictions
    private var restriction: AnyView? {
        if kind == .court && !plan.courtsIncluded {
            return AnyView(EmptyState(title: "Courts come with Ridge", message: "Ridge includes courts, 3 days ahead, at all 5 clubs.", symbol: "figure.pickleball",
                                      actionTitle: "See plans", action: { router.selection = .you; router.paths[.you] = [.membership, .plans] }))
        }
        if kind == .court && model.isTeen && model.currentPerson?.courtsAllowed != true {
            return AnyView(EmptyState(title: "Ask a parent to turn on courts", message: "\(model.member.ownerFirst) can allow courts in Family settings.", symbol: "lock"))
        }
        if kind == .lane && model.isTeen && !(model.currentPerson?.lanesAllowed == true && model.member.age >= 14) {
            return AnyView(EmptyState(title: "Ask a parent to turn on lap lanes", message: "Lanes are for ages 14 and up, with a parent's OK.", symbol: "lock"))
        }
        if kind == .kidsClub && model.isTeen {
            return AnyView(EmptyState(title: "Kids club is for ages 12 and under", message: "Teens 13 to 17 can book Youth classes.", symbol: "face.smiling"))
        }
        let ok: Bool = switch kind { case .court: club.hasCourts; case .lane: club.hasPool; case .kidsClub: club.hasKids }
        if !ok {
            let what = kind == .court ? "courts" : (kind == .lane ? "lap lanes" : "a kids club")
            return AnyView(EmptyState(title: "No \(what) at \(club.fullName)", message: "These clubs have \(what).", symbol: "mappin.slash"))
        }
        if kind == .court && club.courts(for: router.sport) == 0 {
            return AnyView(EmptyState(title: "No \(router.sport.title.lowercased()) here", message: "Pick another sport.", symbol: "figure.pickleball"))
        }
        if model.member.plan == .trailhead && club.id != model.member.homeClubID {
            return AnyView(EmptyState(title: "Your Trailhead plan covers \(model.homeClub.fullName)", message: "Ridge adds all 5 clubs.", symbol: "mappin.slash",
                                      actionTitle: "See plans", action: { router.selection = .you; router.paths[.you] = [.membership, .plans] }))
        }
        return nil
    }

    // MARK: Rows
    /// The status line under a row's glance. `noun` is empty for courts ("2 of 4 open").
    private func slotStatus(open: Int, total: Int, noun: String, past: Bool, paused: Bool, shared: Int = 0) -> String {
        if paused { return "Booking paused" }
        if past { return "Started" }
        if open == 0 && shared == 0 { return "Full" }
        // With lanes to share, the glance already shows the total, so the line stays short enough for one line.
        if shared > 0 { return "\(open) open · \(shared) to share" }
        let n = noun.isEmpty ? "" : " \(noun)"
        return open == total ? "All \(total)\(n) open" : "\(open) of \(total)\(n) open"
    }

    @ViewBuilder private func courtRows(_ day: Date) -> some View {
        let slots = model.courtSlots(club: club, sport: router.sport, day: day, duration: router.duration)
        let blocked = model.bookingBlock != nil
        ForEach(TimeOfDay.allCases.filter { $0 != .early }, id: \.self) { tod in
            let items = slots.filter { TimeOfDay.of($0.start) == tod || (tod == .morning && TimeOfDay.of($0.start) == .early) }
            if !items.isEmpty {
                Section {
                    ForEach(items) { s in
                        Button {
                            guard !s.past, !s.free.isEmpty, !blocked else { return }
                            router.present(.reserve(ReserveRequest(kind: .court, clubID: club.id, start: s.start, sport: router.sport, duration: router.duration)))
                        } label: {
                            let total = club.courts(for: router.sport)
                            let bookable = !s.past && !blocked
                            ReserveSlotRow(start: s.start, end: s.start.addingTimeInterval(Double(router.duration) * 60),
                                           status: slotStatus(open: s.free.count, total: total, noun: "", past: s.past, paused: blocked),
                                           pill: bookable && !s.free.isEmpty ? "Book" : nil, past: s.past,
                                           a11yDetail: bookable && !s.free.isEmpty ? (s.free.count == 1 ? "Court \(s.free[0]) open" : "Courts \(s.free.map(String.init).joined(separator: ", ")) open") : nil) {
                                CourtTiles(total: total, open: bookable ? s.free : [])
                            }
                        }
                        // Not .disabled: that greys a full row like a past one. The row says Full itself.
                        .buttonStyle(.plain).allowsHitTesting(!s.past && !s.free.isEmpty && !blocked)
                    }
                } header: { DetailSectionHeader(title: tod == .morning ? "Morning" : tod.rawValue) }
            }
        }
    }

    @ViewBuilder private func laneRows(_ day: Date) -> some View {
        let slots = model.laneSlots(club: club, day: day)
        let blocked = model.bookingBlock != nil
        ForEach([TimeOfDay.early, .morning, .midday, .evening], id: \.self) { tod in
            let items = slots.filter { TimeOfDay.of($0.start) == tod }
            if !items.isEmpty {
                Section {
                    ForEach(items) { s in
                        Button {
                            guard !s.past, s.bookable > 0, !blocked else { return }
                            router.present(.reserve(ReserveRequest(kind: .lane, clubID: club.id, start: s.start, sport: nil, duration: 45)))
                        } label: {
                            let bookable = !s.past && !blocked
                            ReserveSlotRow(start: s.start, end: s.start.addingTimeInterval(45 * 60),
                                           status: s.bookable == 0 && bookable ? "Full · no waitlist" : slotStatus(open: s.open, total: club.lanes, noun: "lanes", past: s.past, paused: blocked, shared: s.shared),
                                           pill: bookable && s.bookable > 0 ? "Book" : nil, past: s.past) {
                                LaneStrips(swimmers: s.swimmers, bookable: bookable)
                            }
                        }
                        .buttonStyle(.plain).allowsHitTesting(!s.past && s.bookable > 0 && !blocked)
                    }
                } header: { DetailSectionHeader(title: tod.rawValue) }
            }
        }
    }

    @ViewBuilder private func kidsRows(_ day: Date) -> some View {
        if AZ.cal.component(.weekday, from: day) == 1 {
            Section { Label("Kids club is closed on Sundays.", systemImage: "moon.zzz") }
        } else {
            let blocks = model.kidsBlocks(club: club, day: day)
            Section {
                ForEach(blocks) { b in
                    Button {
                        guard !b.past else { return }
                        if b.spotsLeft == 0 { router.present(.reserve(ReserveRequest(kind: .kidsClub, clubID: club.id, start: b.start, sport: nil, duration: 120, block: b.index))) }
                        else { router.present(.reserve(ReserveRequest(kind: .kidsClub, clubID: club.id, start: b.start, sport: nil, duration: 120, block: b.index))) }
                    } label: {
                        let low = b.spotsLeft > 0 && b.spotsLeft <= 3
                        ReserveSlotRow(start: b.start, end: b.end,
                                       status: b.past ? "Started" : (b.spotsLeft == 0 ? "Full" : "\(b.spotsLeft) of \(b.capacity) spots left"),
                                       pill: b.past ? nil : (b.spotsLeft == 0 ? "Join waitlist" : "Book"), past: b.past) {
                            // How full the block is, on the brand's rib meter; warning when 3 or fewer spots are left.
                            RibMeter(value: b.spotsLeft == 0 ? 5 : Int((Double(b.capacity - b.spotsLeft) / Double(max(b.capacity, 1)) * 5).rounded(.up)),
                                     tone: low ? .warning : .brand, size: .sm, peak: false)
                        }
                    }
                    .buttonStyle(.plain).allowsHitTesting(!b.past)
                }
            } header: { DetailSectionHeader(title: "Blocks") }
        }
    }
}

// MARK: - Explore

/// Browse the day's classes by kind and by coach, above the schedule. Each tile and portrait is a filter: a tap
/// shows only that kind or coach, and a second tap clears it. Both read and write `router.filters`, the same
/// filters as the Filters sheet.
struct ClassExploreSections: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        // The day's classes before filters, so every kind and coach stays on offer while one is picked.
        let day = model.sessions(club: model.currentClubID, day: router.day)
        let kinds = ClassCategory.allCases.compactMap { c -> CategoryCount? in
            let n = day.filter { $0.category == c }.count
            return n > 0 ? CategoryCount(category: c, count: n) : nil
        }
        let coachIDs = day.map(\.coachID).reduce(into: [CoachID]()) { if !$0.contains($1) { $0.append($1) } }
        let coaches = coachIDs.map { model.coach($0) }
        if kinds.count > 1 {
            CardStripSection(items: kinds, count: 5, span: 2) {
                DetailSectionHeader(title: "Browse")
            } card: { k in
                let on = router.filters.categories == [k.category]
                ExploreTile(title: k.category.title, detail: k.count == 1 ? "1 class" : "\(k.count) classes",
                            tint: k.category.color, textTint: k.category.textColor, selected: on) {
                    router.filters.categories = on ? [] : [k.category]
                } art: {
                    ClassGraphic(category: k.category, variant: .square)
                }
            }
        }
        if coaches.count > 1 {
            CardStripSection(items: coaches, count: 5, span: 1, axCount: 5, axSpan: 2) {
                DetailSectionHeader(title: "Coaches")
            } card: { c in
                let on = router.filters.coachID == c.id
                PortraitChip(name: c.fullName, label: String(c.fullName.split(separator: " ").first ?? ""), category: c.category, selected: on) {
                    router.filters.coachID = on ? nil : c.id
                }
            }
        }
    }
}

private struct CategoryCount: Identifiable {
    var category: ClassCategory
    var count: Int
    var id: ClassCategory { category }
}
