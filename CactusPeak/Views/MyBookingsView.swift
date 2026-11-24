import SwiftUI

/// Every booking in one place, from Today, Book, Family and the bookings link. The Upcoming and Past control sits in
/// a bar over the list, as on the Book page, so the list scrolls under it with a hard edge. Rows use the booking
/// tiles from Today, grouped by day (upcoming) or by month (past), like the lists in Calendar and Wallet.
struct MyBookingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var tab = Tab.upcoming
    @Environment(\.dynamicTypeSize) private var dts

    enum Tab: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", past = "Past"
        var id: Self { self }
    }

    var body: some View {
        List {
            switch tab {
            case .upcoming: upcoming
            case .past: past
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .safeAreaBar(edge: .top, spacing: 0) { tabPicker }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle("Bookings").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private var tabPicker: some View {
        Group {
            let picker = Picker("Show", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
            if dts.isAccessibilitySize { picker.pickerStyle(.menu) } else { picker.pickerStyle(.segmented) }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 4).padding(.bottom, 10)
    }

    // MARK: Upcoming

    @ViewBuilder private var upcoming: some View {
        let list = model.upcomingBookings
        if list.isEmpty {
            Section {
                EmptyState(title: "No classes booked yet", message: "Pick a class and we'll save your spot.", symbol: "ticket", actionTitle: "Book a class") { router.selection = .book }
            }
            .listRowBackground(Color.clear)
        }
        if model.strikesIn30 > 0 { strikesSection }
        let waits = list.filter { $0.status == .hold } + list.filter { $0.status == .waitlisted }
        if !waits.isEmpty {
            Section {
                ForEach(waits) { row($0) }
            } header: {
                DetailSectionHeader(title: "Waitlist", detail: "\(model.activeWaitlists) of 5")
            }
        }
        let byDay = Dictionary(grouping: list.filter { $0.status == .booked }, by: { $0.start.startOfAZDay })
        ForEach(byDay.keys.sorted(), id: \.self) { d in
            let day = byDay[d] ?? []
            Section {
                ForEach(day) { row($0) }
            } header: {
                DetailSectionHeader(title: dayTitle(d), detail: day.count == 1 ? nil : "\(day.count) booked")
            }
        }
        if model.strikesIn30 == 0 && !list.isEmpty {
            Section {
                NavigationLink(value: AppRoute.strikes) { DetailFactRow(symbol: "info.circle", text: "How strikes work") }
            } footer: {
                Text("A no-show counts as a late cancel.")
            }
        }
    }

    /// Late cancels, as one row that opens the rules: the count in the warning colour, and the limit in the footer.
    private var strikesSection: some View {
        let n = model.strikesIn30
        return Section {
            NavigationLink(value: AppRoute.strikes) {
                DetailFactRow(symbol: "exclamationmark.triangle", text: "\(n) of 3 late cancels", tint: .statusWarning)
            }
            .accessibilityHint("Shows how strikes work")
        } footer: {
            Text("3 late cancels in 30 days pause new bookings for 3 days. A no-show counts as a late cancel.")
        }
    }

    private func dayTitle(_ d: Date) -> String {
        if AZ.cal.isDate(d, inSameDayAs: model.now) { return "Today" }
        if AZ.cal.isDate(d, inSameDayAs: model.now.addingDays(1)) { return "Tomorrow" }
        return d.cpFormat("EEEE, MMM d")
    }

    private func clubShort(_ b: Booking) -> String {
        b.clubID == model.currentClubID ? "" : model.club(b.clubID).shortName
    }

    @ViewBuilder private func row(_ b: Booking) -> some View {
        let route: AppRoute = b.sessionID.map { .classSession($0) } ?? .bookingDetail(b.id)
        // The day is the section header, so the line starts at the time. Waitlist rows mix days, so they name it.
        let when = b.status == .booked ? b.start.cpTimeShort : "\(dayTitle(b.start.startOfAZDay)) · \(b.start.cpTimeShort)"
        let line = [when, b.placeText(clubShort: clubShort(b))].filter { !$0.isEmpty }.joined(separator: " · ")
        let coach = b.coachID.map { model.coach($0) }
        Group {
            if b.status == .hold {
                // The confirm button is the trailing item, so the row opens the class from its own button.
                HStack(spacing: 12) {
                    Button { router.push(route, on: router.selection) } label: {
                        BookingListRow(booking: b, coach: coach, line: line) { EmptyView() }
                            .contentShape(.rect)
                            .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    BookingStateButton(state: .hold(b.holdExpires ?? model.now), action: { if model.confirmHold(b.id) { model.announceBooked(model.booking(b.id)) } })
                }
            } else {
                NavigationLink(value: route) {
                    BookingListRow(booking: b, coach: coach, line: line) {
                        RowPill(text: b.status == .waitlisted ? "Waitlist #\(b.waitlistPosition)" : "View")
                    }
                    .accessibilityElement(children: .combine)
                }
                .navigationLinkIndicatorVisibility(.hidden)
            }
        }
        .swipeActions(edge: .trailing) {
            if b.status == .waitlisted { Button("Leave", role: .destructive) { model.leaveWaitlist(b.id) } }
            else { Button("Cancel", role: .destructive) { router.requestCancel(b.id) } }
        }
        .swipeActions(edge: .leading) {
            if b.status == .booked { Button { router.present(.calendar(b.id)) } label: { Label("Calendar", systemImage: "calendar.badge.plus") }.tint(Color.brandSecondary) }
        }
        .contextMenu {
            if b.status == .booked {
                Button { router.present(.calendar(b.id)) } label: { Label("Add to calendar", systemImage: "calendar.badge.plus") }
                Button(role: .destructive) { router.requestCancel(b.id) } label: { Label("Cancel booking", systemImage: "xmark") }
            }
        }
        .accessibilityAction(named: "Cancel booking") { router.requestCancel(b.id) }
        .accessibilityAction(named: "Add to calendar") { router.present(.calendar(b.id)) }
    }

    // MARK: Past

    @ViewBuilder private var past: some View {
        let list = Array(model.pastBookings.prefix(40))
        if list.isEmpty {
            Section { EmptyState(title: "No past visits yet.", message: "Classes you attend show here.", symbol: "clock.arrow.circlepath") }
                .listRowBackground(Color.clear)
        }
        // Newest month first, as the list is newest first.
        let months = Dictionary(grouping: list, by: { AZ.cal.dateInterval(of: .month, for: $0.start)?.start ?? $0.start.startOfAZDay })
        ForEach(months.keys.sorted(by: >), id: \.self) { m in
            let items = months[m] ?? []
            Section {
                ForEach(items) { pastRow($0) }
            } header: {
                DetailSectionHeader(title: m.cpFormat(AZ.cal.isDate(m, equalTo: model.now, toGranularity: .year) ? "MMMM" : "MMMM yyyy"),
                                    detail: visitsText(items))
            }
        }
    }

    /// "4 visits", from the attended bookings in the month. Nil when there are none.
    private func visitsText(_ items: [Booking]) -> String? {
        let n = items.filter { $0.status == .attended }.count
        return n == 0 ? nil : (n == 1 ? "1 visit" : "\(n) visits")
    }

    @ViewBuilder private func pastRow(_ b: Booking) -> some View {
        // Only when: the outcome takes the row's end, and the room matters less once the visit is over.
        let line = "\(b.start.cpWeekdayShort), \(b.start.cpDayMonth) · \(b.start.cpTimeShort)"
        BookingListRow(booking: b, coach: b.coachID.map { model.coach($0) }, line: line) { BookingOutcome(status: b.status) }
            .accessibilityElement(children: .combine)
            .swipeActions(edge: .leading) {
                if let sid = b.sessionID, model.session(sid) != nil {
                    Button { router.push(.classSession(sid)) } label: { Label("Book again", systemImage: "arrow.clockwise") }.tint(Color.brandSecondary)
                }
            }
            .contextMenu {
                if let sid = b.sessionID, model.session(sid) != nil {
                    Button { router.push(.classSession(sid)) } label: { Label("Book again", systemImage: "arrow.clockwise") }
                }
                if b.status == .attended && b.feedback == nil {
                    Button { router.present(.feedback(b.id)) } label: { Label("Give feedback", systemImage: "star") }
                }
            }
            .accessibilityAction(named: "Give feedback") { router.present(.feedback(b.id)) }
    }
}

/// How a past booking ended, at the end of its row: a small glyph and one word in the status colour, with no
/// capsule, like the declined and pending marks in Wallet's transaction list.
struct BookingOutcome: View {
    var status: BookingStatus

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch status {
        case .attended: ("Attended", "checkmark.circle.fill", .statusSuccess)
        case .missed: ("Missed", "exclamationmark.triangle.fill", .statusWarning)
        case .lateCancelled: ("Late cancel", "exclamationmark.triangle.fill", .statusWarning)
        default: ("Cancelled", "xmark.circle", Color.secondary)
        }
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small).accessibilityHidden(true)
            Text(text).lineLimit(1)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .fixedSize()
    }
}

/// Late cancels against the limit, like a Fitness award page: three slots that fill with each strike, the count, and
/// when the oldest one clears. Then the dates, and the rules as short glyph rows.
struct StrikesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let recent = model.strikes.filter { $0 > model.now.addingTimeInterval(-30 * 86400) }.sorted()
        List {
            Section {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(i < recent.count ? Color.statusWarning : Color(.tertiarySystemFill))
                                .frame(width: 56, height: 72)
                                .overlay {
                                    if i < recent.count {
                                        Image(systemName: "exclamationmark.triangle.fill").symbolFont(.title2).foregroundStyle(Color(.systemBackground))
                                    }
                                }
                        }
                    }
                    .accessibilityHidden(true)
                    Text("\(recent.count) of 3").brandFont(.numeral(.large))
                    Text(recent.first.map { "The oldest clears on \($0.addingTimeInterval(30 * 86400).cpFormat("EEEE, MMM d"))." } ?? "No late cancels in the last 30 days.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let p = model.pauseUntil, p > model.now {
                        Label("New bookings are paused until \(p.cpWeekdayShort) \(p.cpDayMonth).", systemImage: "pause.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.statusWarning)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(recent.count) of 3 late cancels in the last 30 days")
            }
            if !recent.isEmpty {
                Section {
                    ForEach(recent, id: \.self) { d in
                        DetailFactRow(symbol: "calendar", text: d.cpFormat("EEEE, MMM d"), secondary: "Clears \(d.addingTimeInterval(30 * 86400).cpDayMonth)")
                    }
                } header: { DetailSectionHeader(title: "Your late cancels") }
            }
            Section {
                DetailFactRow(symbol: "arrow.uturn.backward", text: "Cancel free up to 2 hours before", secondary: "Classes, courts and lanes")
                DetailFactRow(symbol: "exclamationmark.triangle", text: "Later counts as a strike", secondary: "So does a no-show", tint: .statusWarning)
                DetailFactRow(symbol: "pause.circle", text: "3 in 30 days pause new bookings", secondary: "For 3 days")
                DetailFactRow(symbol: "checkmark.shield", text: "Kids club has no strikes", secondary: "A pause also allows training, check-in and cancelling")
            } header: { DetailSectionHeader(title: "The rules") }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Strikes").navigationBarTitleDisplayMode(.inline)
    }
}
