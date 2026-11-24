import SwiftUI

/// Today is a List: For you first, then Next up, Coming up, and a pair of summary tiles for the club and the week. A held waitlist spot comes before all of it.
struct TodayView: View {
    /// Toolbar buttons zoom the sheets they open out of themselves (see `zoomSource`).
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var loading = true
    /// The class just rated. Its card stays for the thanks and the note until the member closes it.
    @State private var thankedID: BookingID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            let now = model.now
            let club = model.club(model.currentClubID)
            List {
                if model.offline { Section { OfflineBanner(text: "You're offline. \(model.savedDataText)") }.listRowBackground(Color.clear) }
                statusSection
                // A held spot expires in 30 minutes, so it stays above everything else.
                if let hold = model.activeHold { HoldCard(booking: hold) }

                // Recommended first, then what is already booked, then the club and the week.
                ForYouSection()
                if model.isFrozen, let f = model.freeze {
                    FrozenRow(end: f.end)
                } else {
                    NextUpCard(booking: model.nextBooking, now: now)
                }
                UpcomingSection(now: now)
                TodaySummarySection(club: club, reading: model.busyness(club), now: now, pool: model.poolConditions(club))
                if let b = feedbackCandidate(now) {
                    FeedbackCard(booking: b) { thankedID = b.id } onClose: { withAnimation { thankedID = nil } }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .redacted(reason: loading ? .placeholder : [])
            .refreshable { try? await Task.sleep(for: .milliseconds(500)) }
        }
        .task { try? await Task.sleep(for: .milliseconds(300)); loading = false }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        // The club button stands in for the title. The title stays set for VoiceOver and the back button.
        .toolbar(removing: .title)
        .toolbar { toolbar }
        .sensoryFeedback(.levelChange, trigger: model.busyness(model.club(model.currentClubID)).level)
    }

    // MARK: Toolbar
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { ClubMenuButton() }
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.present(.page(.notifications), zoomFrom: "today.inbox") } label: { Image(systemName: model.unreadCount > 0 ? "bell.badge" : "bell") }
                .barItem()
                .accessibilityLabel("Inbox").accessibilityValue(model.unreadCount > 0 ? "\(model.unreadCount) unread" : "")
        }
        .zoomSource("today.inbox", in: zoomNamespace)
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { router.present(.pass, zoomFrom: "today.pass") } label: { Image(systemName: model.checkedInToday ? "checkmark" : "qrcode") }
                .barItem()
                .accessibilityLabel("Show pass").accessibilityValue(model.checkedInToday ? "Checked in" : "")
        }
        .zoomSource("today.pass", in: zoomNamespace)
    }

    // MARK: Status
    @ViewBuilder private var statusSection: some View {
        let phone = model.club(model.currentClubID).phone
        Group {
            if model.paymentFailedDay >= 15 {
                Banner(tone: .danger, text: "See the front desk. Your pass will not scan until the balance is paid.", actionTitle: "Call \(phone)") { openURL(URL(string: "tel:\(phone.filter(\.isNumber))")!) }
            } else if model.paymentFailedDay >= 8 {
                Banner(tone: .danger, text: "New bookings are paused until you pay. Your pass still works.", actionTitle: "Update payment") { router.selection = .you; router.paths[.you] = [.membership] }
            } else if model.paymentFailedDay >= 1 {
                Banner(tone: .warning, text: "We could not charge your card. Retrying on day 3 and day 6.", actionTitle: "Update payment") { router.selection = .you; router.paths[.you] = [.membership] }
            }
            if let p = model.pauseUntil, p > model.now {
                Banner(tone: .warning, text: "New bookings are paused until \(p.cpWeekdayShort) \(p.cpDayMonth). Kids club, check-in and cancelling still work.", actionTitle: "How strikes work") { router.push(.strikes) }
            }
            if let d = model.membershipCancelOn {
                Banner(tone: .info, text: "Cancelling \(d.cpDayMonth). You keep full access until then.", actionTitle: "Reinstate") { model.reinstate() }
            }
        }
        .listRowBackground(Color.clear).listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func feedbackCandidate(_ now: Date) -> Booking? {
        model.bookings.first { $0.status == .attended && ($0.feedback == nil || $0.id == thankedID) && $0.kind == .classSession && now.timeIntervalSince($0.end) < 24 * 3600 && now > $0.end }
    }
}

extension FreezeState { var restartText: String { end.addingDays(1).cpDayMonth } }

struct FrozenRow: View {
    @Environment(AppRouter.self) private var router
    var end: Date
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(text: "Frozen until \(end.cpDayMonth)", symbol: "pause.fill", tone: .neutral)
                Text("Your bookings in the freeze were cancelled with no strikes. You can't check in until billing restarts on \(end.addingDays(1).cpDayMonth).").font(.subheadline)
                Button("View freeze") { router.selection = .you; router.paths[.you] = [.membership, .freeze] }.linkAction()
            }
        }
    }
}

// MARK: - Hold

struct HoldCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var booking: Booking
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("A spot opened in \(booking.title)", systemImage: "bell.badge.fill").font(.headline)
                Text("\(booking.start.cpWeekdayShort) \(booking.start.cpTimeShort) · \(model.club(booking.clubID).fullName). Confirm within 30 minutes or the spot goes to the next person.").font(.subheadline)
                BookingStateButton(state: .hold(booking.holdExpires ?? model.now), size: .large, action: {
                    if model.confirmHold(booking.id) { model.announceBooked(model.booking(booking.id)) }
                }, onRelease: { model.releaseHold(booking.id) })
            }
            .sensoryFeedback(.warning, trigger: booking.id)
        }
        .listRowBackground(Color.statusWarningSubtle)
    }
}

// MARK: - Next up

struct NextUpCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dts
    var booking: Booking?
    var now: Date

    var body: some View {
        if let b = booking { booked(b) } else { empty }
    }

    /// A Books "Continue" style card: the booking's tile, its name, who and where, and when, on a flat tint of its
    /// category. A "…" menu holds the other actions. The card holds no pass button: the pass lives in the toolbar
    /// and in the tab bar accessory, and the booking's own page leads with it on the day.
    private func booked(_ b: Booking) -> some View {
        let session = b.sessionID.flatMap { model.session($0) }
        let club = model.club(b.clubID)
        let secs = max(0, b.start.timeIntervalSince(now))
        let inProgress = now >= b.start
        let route: AppRoute = b.sessionID.map { .classSession($0) } ?? .bookingDetail(b.id)
        // Who or what, then where. Each part shows once: a kids club booking's detail is the children's names. The club
        // shows only when it is not the club in the toolbar.
        let who: String = b.coachID.map { model.coach($0).shortName } ?? ""
        let what: String = session?.room ?? b.detail
        let whereText = b.clubID == model.currentClubID ? "" : club.shortName
        let secondary = [who, what, whereText].filter { !$0.isEmpty }.joined(separator: " · ")
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Button { router.push(route, on: .today) } label: {
                        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                        layout {
                            BookingTile(booking: b, coach: b.coachID.map { model.coach($0) }, size: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.title).brandFont(.section).fixedSize(horizontal: false, vertical: true)
                                if !secondary.isEmpty { Text(secondary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                HStack(spacing: 4) {
                                    Text(b.start.cpTimeShort).monospacedDigit()
                                    Text("·")
                                    trailing(b, secs: secs, inProgress: inProgress)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(b.category.textColor)
                                if model.checkedInToday {
                                    Label("Checked in", systemImage: "checkmark.circle.fill")
                                        .font(.footnote.weight(.semibold)).foregroundStyle(Color.statusSuccess)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Next up. \(b.title), \(b.start.cpTimeShort), \(inProgress ? "in progress" : "starts in \(max(Int(secs / 60), 1)) minutes"), \(who), \(what), \(club.fullName).\(session.map { " Intensity \($0.intensity) of 5." } ?? "")")
                    .accessibilityHint("Opens the booking")
                    moreMenu(b, club)
                }
            }
            .padding(.vertical, 4)
        } header: { DetailSectionHeader(title: "Next up") }
        .listRowBackground(NextUpTint(category: b.category))
    }

    /// The countdown, "In progress", "Today" or the weekday. It sits after the start time.
    @ViewBuilder private func trailing(_ b: Booking, secs: Double, inProgress: Bool) -> some View {
        if inProgress {
            Text("In progress")
        } else if secs < 5400 {
            Text(timerInterval: Date.now...Date.now.addingTimeInterval(max(secs, 1)), countsDown: true, showsHours: false)
                .monospacedDigit()
        } else {
            Text(AZ.cal.isDate(b.start, inSameDayAs: now) ? "Today" : b.start.cpWeekdayShort)
        }
    }

    /// Directions, calendar and cancel, behind one "…" button in the card's corner.
    private func moreMenu(_ b: Booking, _ club: Club) -> some View {
        Menu {
            Button { openMaps(club) } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
            if b.kind == .classSession { Button { router.present(.calendar(b.id)) } label: { Label("Add to calendar", systemImage: "calendar.badge.plus") } }
            Button(role: .destructive) { router.requestCancel(b.id) } label: { Label("Cancel booking", systemImage: "xmark") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .tint(.primary)
        .accessibilityLabel("More")
    }

    private func openMaps(_ c: Club) {
        if let u = URL(string: "http://maps.apple.com/?daddr=\(c.latitude),\(c.longitude)&q=\(c.fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") { openURL(u) }
    }

    @ViewBuilder private var empty: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing booked today.").brandFont(.section)
                if let u = model.usualSession {
                    let d = model.rowData(u)
                    let day = AZ.cal.isDate(u.start, inSameDayAs: now) ? "Today" : (AZ.cal.isDate(u.start, inSameDayAs: now.addingDays(1)) ? "Tomorrow" : u.start.cpWeekdayShort)
                    Text("Your usual: \(u.name), \(day) \(u.start.cpTimeShort) · \(d.left) \(u.spotNoun) left").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        BookingStateButton(state: d.state, action: { ClassActions.primary(u, model: model, router: router) })
                        Button("Browse classes") { router.selection = .book }.linkAction()
                    }
                } else {
                    Button("Browse classes") { router.selection = .book }.primaryAction()
                }
            }
        } header: { DetailSectionHeader(title: "Next up") }
    }
}

extension AppModel {
    /// The most-attended class name at the home club, next time it runs.
    var usualSession: ClassSession? {
        let counts = Dictionary(grouping: bookings.filter { $0.status == .attended }, by: \.title).mapValues(\.count)
        guard let name = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return sessions.first { $0.name == name && $0.clubID == member.homeClubID && $0.start > now && booking(forSession: $0.id) == nil && visible($0) }
    }
}

// MARK: - Coming up

struct UpcomingSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var now: Date
    private func dayText(_ d: Date) -> String {
        if AZ.cal.isDate(d, inSameDayAs: now) { return "Today" }
        if AZ.cal.isDate(d, inSameDayAs: now.addingDays(1)) { return "Tomorrow" }
        return d.cpWeekdayShort
    }
    var body: some View {
        let list = Array(model.upcomingBookings.filter { $0.id != model.nextBooking?.id }.prefix(3))
        if !list.isEmpty {
            Section {
                ForEach(list) { b in
                    NavigationLink(value: b.sessionID.map { AppRoute.classSession($0) } ?? AppRoute.bookingDetail(b.id)) {
                        BookingListRow(booking: b, coach: b.coachID.map { model.coach($0) },
                                       line: [dayText(b.start) + " · " + b.start.cpTimeShort,
                                              b.clubID == model.currentClubID ? "" : model.club(b.clubID).shortName]
                                           .filter { !$0.isEmpty }.joined(separator: " · ")) {
                            RowPill(text: b.status == .waitlisted ? "Waitlist #\(b.waitlistPosition)" : "View")
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .swipeActions(edge: .trailing) {
                        if b.status == .waitlisted { Button("Leave") { model.leaveWaitlist(b.id) }.tint(.red) }
                        else { Button("Cancel") { router.requestCancel(b.id) }.tint(.red) }
                    }
                }
            } header: {
                let total = model.upcomingBookings.count
                DetailSectionHeader(title: "Coming up", detail: "\(total) booked") { router.push(.myBookings, on: .today) }
            }
        }
    }
}

// MARK: - For you

struct ForYouSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let picks = suggestions()
        if !picks.isEmpty {
            CardStripSection(items: picks) {
                DetailSectionHeader(title: "For you", detail: picks.count == 1 ? "1 class" : "\(picks.count) classes")
            } card: { d in
                Button { router.push(.classSession(d.session.id), on: .today) } label: {
                    ClassFeatureCard(data: d)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func suggestions() -> [ClassRowData] {
        let tomorrow = model.now.startOfAZDay.addingDays(1)
        let interests = model.prefs.interests
        var out: [ClassSession] = []
        for off in 0..<3 {
            out += model.sessions(club: model.member.homeClubID, day: tomorrow.addingDays(off))
                .filter { interests.contains($0.category) && model.state(for: $0).isBookable && model.booking(forSession: $0.id) == nil }
        }
        return out.sorted { $0.start < $1.start }.prefix(3).map { model.rowData($0) }
    }
}

// MARK: - Feedback

/// A quick check after a class, like rating a place in Apple Maps: the class, then one "Overall" row with a thumbs
/// up and a thumbs down. One tap answers. The card then thanks the member and offers a note, until they close it.
struct FeedbackCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var booking: Booking
    /// Called after an answer, so Today keeps the card on screen for its thanks.
    var onAnswer: () -> Void = {}
    var onClose: () -> Void = {}

    private var answer: Answer? { booking.feedback.flatMap(Answer.init(rawValue:)) }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                BookingTile(booking: booking, coach: booking.coachID.map { model.coach($0) }, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer == nil ? "How was \(booking.title)?" : "Thanks for telling us").font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
                if answer != nil {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.glass).buttonBorderShape(.circle).tint(.primary)
                        .accessibilityLabel("Close")
                }
            }
            HStack {
                Text("Overall")
                Spacer(minLength: 8)
                ForEach(Answer.allCases, id: \.self) { a in thumb(a) }
            }
            if answer != nil {
                Button { router.present(.feedback(booking.id)) } label: { Label("Add a note", systemImage: "square.and.pencil") }
            }
        } header: {
            // A title, like Health's "Highlights" or "Blood Pressure Log" over a single card: Today titles every group,
            // so a lone line would be the one odd separator. The title names the kind of card; the card names the class.
            DetailSectionHeader(title: "Feedback")
        } footer: {
            Text("Only the club sees this.")
        }
        .sensoryFeedback(.selection, trigger: booking.feedback)
    }

    /// "Today, 6 am · Marisol V." before an answer; what the answer does after it.
    private var subtitle: String {
        if let answer { return answer == .up ? "Your coach will see it." : "We'll pass it on, and suggest other classes." }
        let coach = booking.coachID.map { " · \(model.coach($0).shortName)" } ?? ""
        return "\(booking.start.cpTimeShort)\(coach)"
    }

    private func thumb(_ a: Answer) -> some View {
        let on = answer == a
        return Button {
            withAnimation(.snappy) { model.giveFeedback(booking.id, a.rawValue) }
            onAnswer()
        } label: {
            Image(systemName: on ? a.symbol + ".fill" : a.symbol)
                .symbolFont(.title3)
                .foregroundStyle(on ? Color.brandOnAccent : Color.secondary)
                .frame(width: 44, height: 44)
                .background(on ? (a == .up ? Color.brandAccent : Color.secondary) : Color(.tertiarySystemFill), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        // One answer per class. Not .disabled: that would fade the chosen thumb.
        .allowsHitTesting(answer == nil)
        .accessibilityLabel(a == .up ? "Liked it" : "Not for me")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private enum Answer: String, CaseIterable {
        case up = "Great", down = "Not for me"
        var symbol: String { self == .up ? "hand.thumbsup" : "hand.thumbsdown" }
    }
}

// MARK: - Summary tiles

/// The club's crowd and the member's week as two tiles side by side. Each opens its full page.
struct TodaySummarySection: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var club: Club
    var reading: BusynessReading
    var now: Date
    /// Nil when the club has no pool. The pool cards then leave the grid.
    var pool: PoolConditions?

    var body: some View {
        Section {
            SummaryTileGrid {
                SummaryTilePair {
                    CrowdCard(club: club, reading: reading, now: now)
                    VisitsCard()
                }
                if let pool { PoolTiles(club: club, pool: pool) }
            }
        } header: {
            DetailSectionHeader(title: "Summary")
        }
    }
}

/// The pool's row of the summary grid: the water temperature, then the shade sails where the club has them, or the
/// lanes open now where it does not.
private struct PoolTiles: View {
    @Environment(AppRouter.self) private var router
    var club: Club
    var pool: PoolConditions

    var body: some View {
        SummaryTilePair {
            StatCard(title: "Water", symbol: "water.waves", tint: ClassCategory.aqua.textColor,
                     time: pool.readAt.cpTimeShort, value: "\(pool.waterF)", unit: "°F", detail: "Lap pool", action: openClub)
                .accessibilityLabel("Water, \(pool.waterF) degrees Fahrenheit at \(pool.readAt.cpTimeShort)")
            if let shade = pool.shade {
                StatCard(title: "Shade sails", symbol: shade.up ? "sun.max.fill" : "sun.horizon.fill", tint: Color.dawnCopper,
                         time: "Now", value: shade.up ? "Up" : "Down", unit: nil,
                         detail: "\(shade.up ? "Down" : "Up") at \(shade.next.cpTimeShort)\(AZ.cal.isDate(shade.next, inSameDayAs: pool.readAt) ? "" : " tomorrow")",
                         action: openClub)
            } else if let open = pool.lanesOpen {
                StatCard(title: "Lanes", symbol: "figure.pool.swim", tint: ClassCategory.aqua.textColor,
                         time: "Now", value: "\(open)", unit: "of \(pool.laneCount)", detail: "Open to book", action: openLanes)
            } else {
                StatCard(title: "Lanes", symbol: "figure.pool.swim", tint: ClassCategory.aqua.textColor,
                         time: nil, value: "Closed", unit: nil,
                         detail: pool.opens.map { "Opens \($0.cpTimeShort)" }, action: openLanes)
            }
        }
    }

    private func openClub() { router.push(.club(club.id), on: .today) }
    private func openLanes() { router.segment = .lanes; router.selection = .book }
}

/// The crowd at the current club now, on the rib meter, and how long the club stays open. The club's name is in
/// the bar, so the card does not repeat it.
private struct CrowdCard: View {
    @Environment(AppRouter.self) private var router
    var club: Club
    var reading: BusynessReading
    var now: Date

    var body: some View {
        StatCard(title: "Crowd", symbol: "person.2.fill", tint: Color.brandSecondary,
                 time: reading.stale ? nil : "Now",
                 value: reading.closed ? "Closed" : (reading.stale ? "Unavailable" : reading.word), unit: nil,
                 detail: club.isOpen(at: now) ? "Open until \(club.openUntilText(on: now))" : "Opens \(club.opensText(now))") {
            router.push(.club(club.id), on: .today)
        } visual: {
            if !reading.closed { RibMeter(value: reading.level, tone: reading.tone, size: .md, unavailable: reading.stale) }
        }
    }
}

/// Visits this week against the goal, then the week as a row of days, like the week strip in Fitness: a filled dot
/// for a day with a visit, a ring for today, each over its initial.
private struct VisitsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let ws = model.weekStart(model.now)
        let today = AZ.cal.dateComponents([.day], from: ws, to: model.now.startOfAZDay).day ?? 0
        let visited: [Bool] = (0..<7).map { i in
            let d = ws.addingDays(i)
            return model.visits.contains { $0 >= d && $0 < d.addingDays(1) && $0 <= model.now }
        }
        StatCard(title: "This week", symbol: "calendar", tint: Color.linkText, time: nil,
                 value: "\(model.visitsThisWeek)", unit: "of \(model.weeklyGoal) visits",
                 detail: model.visits.isEmpty ? "Your first visit starts a streak" : "\(model.streak.weeks)-week streak") {
            router.push(.progress, on: .today)
        } visual: {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(visited[i] ? Color.brandAccent : Color(.tertiarySystemFill))
                            .overlay { if i == today && !visited[i] { Circle().strokeBorder(Color.brandAccent, lineWidth: 1.5) } }
                            .frame(width: 11, height: 11)
                        Text(ws.addingDays(i).cpFormat("EEEEE")).font(.caption2.weight(i == today ? .bold : .regular))
                            .foregroundStyle(i == today ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Visits this week, \(model.visitsThisWeek) of \(model.weeklyGoal). \(visited.filter { $0 }.count) days with a visit.")
    }
}

/// The Next up card's fill: the card colour with a flat tint of the booking's category on top.
private struct NextUpTint: View {
    var category: ClassCategory
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            category.color.opacity(scheme == .dark ? 0.22 : 0.12)
        }
    }
}
