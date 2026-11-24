import SwiftUI

struct ClassDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    /// The pass zooms out of the button that opens it.
    @Environment(\.zoomNamespace) private var zoomNamespace
    let sessionID: SessionID
    @State private var titleHidden = false
    /// True once the intro's booking control has scrolled under the bar.
    @State private var bookingHidden = false

    var body: some View {
        if let s = model.session(sessionID) {
            content(s)
        } else {
            ContentUnavailableView("Class not found", systemImage: "calendar.badge.exclamationmark", description: Text("It may have been removed. Go back to the schedule."))
        }
    }

    private func content(_ s: ClassSession) -> some View {
        let coach = model.coach(s.coachID)
        let club = model.club(s.clubID)
        let st = model.state(for: s)
        let left = model.spotsLeft(s)
        return List {
            // A class is media, so it leads with its art, full width under the bar, as a Fitness+ workout does.
            HeroHeaderSection(height: 300) {
                ClassGraphic(category: s.category, variant: .wide).accessibilityHidden(true)
            } content: {
                intro(s, coach: coach)
                booking(s, st)
                actions(s, club: club)
            }
            stats(s, left: left, club: club)
            if hasStateLine(st) { Section { stateLine(s, st) } }
            details(s, club: club)
            Section {
                Text(s.summary)
            } header: { DetailSectionHeader(title: "About") }
            alsoThisWeek(s)
            CancelPolicySection(cutoff: s.start.addingTimeInterval(-2 * 3600), waitlistUntil: s.start.addingTimeInterval(-3600),
                                countsAsStrike: true)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .heroPage(heroVisible: !titleHidden)
        .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        .navigationTitle(s.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailBarTitle(title: s.name, shown: titleHidden)
            }
            // When the intro scrolls away, its booking control follows the name into the bar, in compact form.
            // A booked class puts the pass there instead: cancel is not an action to keep one tap away.
            if bookingHidden {
                if case .booked = st {
                    ToolbarItem(placement: .topBarTrailing) {
                        DetailBarPassButton(sourceID: "class.pass.bar")
                    }
                    .zoomSource("class.pass.bar", in: zoomNamespace)
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                } else if let title = barTitle(st) {
                    ToolbarItem(placement: .topBarTrailing) {
                        DetailBarButton(title: title) { ClassActions.primary(s, model: model, router: router) }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.toggleFavourite(session: s.id) } label: { Image(systemName: model.favouriteSessions.contains(s.id) ? "heart.fill" : "heart") }
                    .barItem()
                    .accessibilityLabel(model.favouriteSessions.contains(s.id) ? "Remove favourite" : "Favourite")
                    .sensoryFeedback(.selection, trigger: model.favouriteSessions)
            }
        }
    }

    /// The bar shows only actions the member can take now. Other states stay in the intro.
    private func barTitle(_ st: BookingState) -> String? {
        switch st {
        case .book, .dropIn: "Book"
        case .waitlist: "Waitlist"
        case .hold: "Confirm"
        default: nil
        }
    }

    private func hasStateLine(_ st: BookingState) -> Bool {
        switch st {
        case .waitlisted, .hold, .started, .dropIn, .restricted: true
        default: false
        }
    }

    @ViewBuilder private func stateLine(_ s: ClassSession, _ st: BookingState) -> some View {
        switch st {
        case .waitlisted(let n): Label("You're #\(n) on the waitlist. We'll tell you if a spot opens.", systemImage: "clock").font(.subheadline.weight(.semibold))
        case .hold(let until):
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let secs = max(0, Int(until.timeIntervalSince(model.now)))
                Label("A spot opened. Confirm in \(String(format: "%d:%02d", secs / 60, secs % 60)).", systemImage: "bell.badge.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.statusWarning)
            }
        case .started: Label(model.now > s.end ? "This class has ended." : "This class has started.", systemImage: "info.circle").font(.subheadline)
        case .restricted(let rr): Label("\(rr.label). \(rr.note)", systemImage: "lock.fill").font(.subheadline.weight(.semibold))
        case .dropIn(let n): Label("Drop-in · \(n) spot\(n == 1 ? "" : "s") left. Waitlist is closed.", systemImage: "info.circle").font(.subheadline)
        default: EmptyView()
        }
    }

    /// The name, the date and time, the coach, then the tags, aligned to the leading edge under the art.
    private func intro(_ s: ClassSession, coach: Coach) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.name)
                .brandFont(.title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .onScrollVisibilityChange(threshold: 0.2) { titleHidden = !$0 }
            Text("\(s.start.cpFormat("EEEE, MMM d")) · \(s.start.cpTimeShort)–\(s.end.cpTimeShort)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            DetailCoachLine(coach: coach, category: s.category)
            FlowLayout(spacing: 6) { tagItems(s) }
        }
        // An explicit colour for the text: inside a header, the hierarchical `.primary` resolves to secondary.
        .foregroundStyle(Color.primary)
    }

    /// The category badge and the age and first-timer tags.
    @ViewBuilder private func tagItems(_ s: ClassSession) -> some View {
        CategoryBadge(category: s.category)
        if s.minAge >= 18 { DetailTag(text: "Ages 18+") }
        else if s.teenOK { DetailTag(text: "Teen OK") }
        if s.firstTimers { DetailTag(text: "First-timers welcome", symbol: "leaf.fill", tint: .statusSuccess) }
    }

    /// Calendar (when booked), invite (when the member has guest passes) and share, as equal buttons.
    private func actions(_ s: ClassSession, club: Club) -> some View {
        let current = model.booking(forSession: s.id)
        let booked: Booking? = current?.status == .booked ? current : nil
        return DetailActionRow {
            if let b = booked {
                Button { router.present(.calendar(b.id)) } label: { DetailActionLabel(title: "Calendar", symbol: "calendar.badge.plus") }
                    .accessibilityLabel("Add to calendar")
            }
            if model.guestPassesLeft > 0 {
                Button { router.present(.invite(s.id)) } label: { DetailActionLabel(title: "Invite", symbol: "person.badge.plus") }
                    .accessibilityLabel("Invite a friend")
            }
            ShareLink(item: URL(string: "https://app.cactuspeak.example/book/class/\(s.id)")!, subject: Text(s.name),
                      message: Text("\(s.name), \(s.start.cpLongDay) \(s.start.cpTimeShort), \(club.fullName)")) {
                DetailActionLabel(title: "Share", symbol: "square.and.arrow.up")
            }
        }
    }

    /// The four numbers people check first, side by side as in the App Store: how hard, how long, how many spots, and
    /// how busy the club usually is then.
    private func stats(_ s: ClassSession, left: Int, club: Club) -> some View {
        let crowd = club.typicalLevel(at: s.start)
        return Section {
            DetailStatStrip {
                DetailStat(label: "Intensity", detail: Intensity.word(s.intensity)) {
                    RibMeter(value: s.intensity, tone: .category(s.category), size: .md, peak: false)
                }
                DetailStat(label: "Length", number: "\(s.durationMin)", detail: "min")
                DetailStat(label: "Spots", number: left == 0 ? "0" : "\(left)",
                           detail: left == 0 ? "Full" : "of \(s.capacity) left")
                DetailStat(label: "Crowd", detail: BusynessReading.word(crowd),
                           accessibilityText: "Crowd, usually \(BusynessReading.word(crowd).lowercased()) at this time") {
                    RibMeter(value: crowd, tone: .crowd(crowd), size: .md, peak: false)
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// Where it is and what to bring, then the club.
    private func details(_ s: ClassSession, club: Club) -> some View {
        Section {
            DetailFactRow(symbol: "door.left.hand.open", text: s.room)
            if !s.bring.isEmpty { DetailFactRow(symbol: "bag", text: s.bring.joined(separator: ", ")) }
            NavigationLink(value: AppRoute.club(club.id)) {
                DetailFactRow(symbol: "mappin.and.ellipse", text: club.fullName, secondary: "\(club.city), AZ")
            }
        } header: {
            DetailSectionHeader(title: "Details")
        }
    }

    /// The same class on other days this week, as Calendar lists events: a date leaf, the time and coach, and the
    /// spots left. Every row is the same class, so the rows show no class art.
    @ViewBuilder private func alsoThisWeek(_ s: ClassSession) -> some View {
        let more = model.sessions.filter { $0.name == s.name && $0.clubID == s.clubID && $0.id != s.id && $0.start > model.now && $0.start < model.now.addingDays(8) && model.visible($0) }.prefix(3)
        if !more.isEmpty {
            Section {
                ForEach(Array(more)) { m in
                    let left = model.spotsLeft(m)
                    NavigationLink(value: AppRoute.classSession(m.id)) {
                        HStack(spacing: 12) {
                            DateBadge(date: m.start)
                            VStack(alignment: .leading, spacing: 2) {
                                // The badge names the day, so the row leads with the time.
                                Text(m.start.cpTimeShort).font(.headline).monospacedDigit()
                                Text(model.coach(m.coachID).shortName).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            RowPill(text: left == 0 ? "Full" : "\(left) left")
                        }
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                }
            } header: {
                DetailSectionHeader(title: "Also this week", detail: "\(more.count) more")
            }
        }
    }

    // MARK: Booking (in the intro)
    /// One full-width control. Book carries the plan as its second line; a booked class leads with Cancel, which
    /// carries the time left to cancel free, and puts the pass in a circle button beside it. Other states keep the
    /// plan and cancel line under the control.
    private func booking(_ s: ClassSession, _ st: BookingState) -> some View {
        let b = model.booking(forSession: s.id)
        let plan = model.member.plan == .trailhead && s.clubID != model.member.homeClubID ? "Ridge only" : "Included with \(model.member.plan.name)"
        let ax = dts.isAccessibilitySize
        return VStack(alignment: ax ? .leading : .center, spacing: 8) {
            Group {
                switch st {
                case .book, .dropIn:
                    DetailPrimaryButton(title: "Book", subtitle: plan) { ClassActions.primary(s, model: model, router: router) }
                case .booked:
                    BookedActionRow(cancelCutoff: s.start.addingTimeInterval(-7200), passSourceID: "class.pass") {
                        if let b { router.requestCancel(b.id) }
                    }
                case .started where model.now > s.end:
                    if let b, b.status == .attended {
                        DetailPrimaryButton(title: "Give feedback") { router.present(.feedback(b.id)) }
                    } else { BookingStateButton(state: st, size: .large, action: {}) }
                default:
                    BookingStateButton(state: st, size: .large, action: { ClassActions.primary(s, model: model, router: router) },
                                       onLeave: { if let b { model.leaveWaitlist(b.id) } }, onRelease: { if let b { model.releaseHold(b.id) } })
                }
            }
            .frame(maxWidth: .infinity)
            if showsPlanLine(st) {
                Text("\(plan) · \(cancelLine(s, st))")
                    .font(.footnote).foregroundStyle(Color.secondary)
                    .multilineTextAlignment(ax ? .leading : .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: ax ? .leading : .center)
        .reportsHidden($bookingHidden)
    }

    /// Book and booked carry their line inside the button.
    private func showsPlanLine(_ st: BookingState) -> Bool {
        switch st {
        case .book, .dropIn, .booked: false
        default: true
        }
    }

    private func cancelLine(_ s: ClassSession, _ st: BookingState) -> String {
        let left = model.spotsLeft(s)
        let free = "Free cancel until \(s.start.addingTimeInterval(-7200).cpTimeShort)"
        if left == 0 { return "Full · Waitlist \(model.waitlistCount(s))" }
        return free
    }
}


