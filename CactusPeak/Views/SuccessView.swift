import SwiftUI

/// Confirmation for things that have no list to return to (a freeze). A small hierarchical check, a title, the facts.
/// Bookings do not use this: they confirm inline with a haptic and a toast, and the screen shows Booked.
struct SuccessPattern<Summary: View, Extra: View>: View {
    var headline: String
    var pill: String
    var pillSymbol: String = "checkmark"
    var primaryTitle: String?
    var primaryAction: () -> Void = {}
    var shareText: String?
    @ViewBuilder var summary: () -> Summary
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(headline, systemImage: "checkmark.circle").symbolRenderingMode(.hierarchical).brandFont(.title2).foregroundStyle(Color.statusSuccess)
                    StatusPill(text: pill, symbol: pillSymbol, tone: .success)
                }
                .accessibilityAddTraits(.isHeader)
            }
            Section { summary() }
            if let primaryTitle {
                Section {
                    Button(action: primaryAction) { Label(primaryTitle, systemImage: "calendar.badge.plus") }
                    if let shareText { ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") } }
                }
            }
            Section { extra() }.listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
    }
}

/// Booking detail (from Today, Bookings and toasts) for courts, lanes, kids club and personal training. A booking is
/// a ticket, so the page leads with a pass card like a Wallet boarding pass: the fields people check at a glance, and
/// the check-in code on the day. Cancel, Directions and Calendar follow. Once the card scrolls away, the pass shows
/// in the bar.
struct SuccessView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.dynamicTypeSize) private var dts
    let bookingID: BookingID
    var fresh: Bool
    @State private var titleHidden = false
    @State private var primaryHidden = false

    var body: some View {
        if let b = model.booking(bookingID) {
            content(b)
        } else {
            ContentUnavailableView("Booking not found", systemImage: "ticket", description: Text("It may have been cancelled."))
        }
    }

    private func content(_ b: Booking) -> some View {
        let club = model.club(b.clubID)
        let coach = b.coachID.map { model.coach($0) }
        return List {
            DetailHeaderSection {
                BookingPassCard(booking: b, club: club, coach: coach, titleHidden: $titleHidden)
                    .reportsHidden($primaryHidden)
                control(b)
                actions(b, club: club)
            }
            if b.status == .booked && b.kind == .kids { Section { checkInNote(b) } }
            if b.kind == .pt, let coach {
                Section {
                    NavigationLink(value: AppRoute.coach(coach.id)) { CoachCard(coach: coach) }
                } header: { DetailSectionHeader(title: "Coach") }
            }
            Section {
                NavigationLink(value: AppRoute.club(club.id)) {
                    DetailFactRow(symbol: "mappin.and.ellipse", text: club.fullName, secondary: "\(club.city), AZ")
                }
            } header: { DetailSectionHeader(title: "Club") }
            if b.status == .booked { cancellation(b) }
            if b.status == .booked && b.kind == .classSession {
                @Bindable var model = model
                Section { Toggle("Show on Lock Screen", isOn: $model.prefs.liveActivities) } footer: { Text("Appears 1 hour before class.") }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(b.status == .waitlisted ? "Waitlist" : "Booking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) { DetailBarTitle(title: b.title, shown: titleHidden) }
            // Once the pass card scrolls away, the pass is one tap away in a bar item that never overflows.
            if primaryHidden && b.status == .booked {
                ToolbarItem(placement: .topBarPinnedTrailing) { DetailBarPassButton(sourceID: "booking.pass.bar") }
                    .zoomSource("booking.pass.bar", in: zoomNamespace)
            }
        }
    }

    // MARK: Main control and actions

    @ViewBuilder private func control(_ b: Booking) -> some View {
        switch b.status {
        case .booked:
            // The pass card is the page's main object, so cancel is a quiet glass button under it, not the lead.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Button(role: .destructive) { router.requestCancel(b.id) } label: {
                    VStack(spacing: 1) {
                        Text("Cancel booking").fontWeight(.semibold)
                        Text(CancelText.left(until: b.cancelCutoff(), now: model.now)).font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(dts.isAccessibilitySize ? .roundedRectangle(radius: DetailMetrics.cornerRadius) : .capsule)
            }
        case .waitlisted:
            DetailPrimaryButton(title: "Leave waitlist", subtitle: "We can offer you a spot until \(b.start.addingTimeInterval(-3600).cpTimeShort)",
                                role: .destructive) {
                model.leaveWaitlist(b.id); router.goBack()
            }
        default:
            EmptyView()
        }
    }

    /// Directions, then Calendar while booked, then Invite for a court (a partner joins) or Call for the rest.
    /// Never more than three, so the buttons keep the class page's width.
    private func actions(_ b: Booking, club: Club) -> some View {
        DetailActionRow {
            Button { openMaps(club) } label: { DetailActionLabel(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond") }
            if b.status == .booked {
                Button { router.present(.calendar(b.id)) } label: { DetailActionLabel(title: "Calendar", symbol: "calendar.badge.plus") }
                    .accessibilityLabel("Add to calendar")
            }
            if b.status == .booked && b.kind == .court {
                ShareLink(item: "\(b.title), \(b.start.cpLongDay) \(b.start.cpTimeShort), \(club.fullName). Join me: https://app.cactuspeak.example/invite/court/\(b.id)") {
                    DetailActionLabel(title: "Invite", symbol: "person.badge.plus")
                }
                .accessibilityLabel("Invite a partner")
            } else {
                Button { openURL(URL(string: "tel:\(club.phone.filter(\.isNumber))")!) } label: { DetailActionLabel(title: "Call", symbol: "phone") }
                    .accessibilityLabel("Call the club")
            }
        }
    }

    /// A short line under the intro for what the member must do, as the class page shows its state line.
    private func checkInNote(_ b: Booking) -> some View {
        Label("Check in by \(b.start.addingTimeInterval(15 * 60).cpTimeShort) or we release the block.", systemImage: "figure.walk.arrival")
            .font(.subheadline.weight(.semibold))
    }

    /// When a cancel stops being free, and what a late one costs, in the class page's rows. Kids club has no strikes;
    /// training shows only its cutoff.
    private func cancellation(_ b: Booking) -> some View {
        CancelPolicySection(cutoff: b.cancelCutoff(),
                            countsAsStrike: [.court, .lane, .classSession].contains(b.kind),
                            note: b.kind == .kids ? "Kids club has no strikes" : nil)
    }

    private func openMaps(_ c: Club) {
        if let u = URL(string: "http://maps.apple.com/?daddr=\(c.latitude),\(c.longitude)") { openURL(u) }
    }
}

/// A booking as a pass, like a boarding pass in Wallet: the tile, name and club, then a grid of labelled fields
/// (date, time, the court or lane or children, the length), and on the day of a booked visit the check-in code.
struct BookingPassCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dts
    var booking: Booking
    var club: Club
    var coach: Coach?
    @Binding var titleHidden: Bool

    var body: some View {
        let b = booking
        let showsCode = b.status == .booked && AZ.cal.isDate(b.start, inSameDayAs: model.now)
        VStack(alignment: .leading, spacing: 18) {
            // Tile, name and status in a row; stacked at accessibility sizes so the name has the full width.
            (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                BookingTile(booking: b, coach: coach, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.title).brandFont(.section).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .onScrollVisibilityChange(threshold: 0.2) { titleHidden = !$0 }
                    Text(club.shortName).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !dts.isAccessibilitySize { Spacer(minLength: 8) }
                statusTag(b)
            }
            fields(b)
            if showsCode { code }
        }
        .padding(20)
        .foregroundStyle(Color.primary)
        .background {
            // The card colour with a flat tint of the booking's category, as a pass carries its issuer's colour.
            ZStack {
                Color(.secondarySystemGroupedBackground)
                b.category.color.opacity(scheme == .dark ? 0.18 : 0.08)
            }
            .clipShape(.rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    /// Two columns of fields; one column at accessibility sizes.
    @ViewBuilder private func fields(_ b: Booking) -> some View {
        let items = [
            ("Date", b.start.cpFormat("EEE, MMM d")),
            ("Time", "\(b.start.cpTimeShort)–\(b.end.cpTimeShort)"),
            placeField(b),
            ("Length", Duration.seconds(b.end.timeIntervalSince(b.start)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))),
        ].compactMap { $0 }
        let columns = dts.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    Text(item.1).font(.headline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The court, the lane, the children or the coach, named by what it is.
    private func placeField(_ b: Booking) -> (String, String)? {
        switch b.kind {
        case .court: ("Court", b.detail.replacingOccurrences(of: "Court ", with: ""))
        case .lane: ("Lane", b.detail.replacingOccurrences(of: "Lane ", with: ""))
        case .kids: (b.people.count == 1 ? "Child" : "Children", b.detail)
        case .pt: coach.map { ("Coach", $0.fullName) }
        case .classSession: b.detail.isEmpty ? nil : ("Room", b.detail)
        }
    }

    /// The member's check-in code, as a pass shows its barcode at the bottom.
    private var code: some View {
        VStack(spacing: 8) {
            if model.checkedInToday {
                Label("Checked in", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Color.statusSuccess)
            } else {
                Image(uiImage: QR.image(model.passCode())).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(12)
                    .background(Color.white, in: .rect(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Check-in code. Show it to the scanner at the front desk.")
                Text("Scan at the front desk").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder private func statusTag(_ b: Booking) -> some View {
        switch b.status {
        case .booked: DetailTag(text: "Booked", symbol: "checkmark", tint: .statusSuccess)
        case .waitlisted: DetailTag(text: "Waitlist #\(b.waitlistPosition)", symbol: "clock")
        case .hold: DetailTag(text: "Spot held", symbol: "bell.badge.fill", tint: .statusWarning)
        case .attended: DetailTag(text: "Attended", symbol: "checkmark", tint: .statusSuccess)
        case .missed: DetailTag(text: "Missed", symbol: "exclamationmark.triangle.fill", tint: .statusWarning)
        case .lateCancelled: DetailTag(text: "Late cancel", symbol: "exclamationmark.triangle.fill", tint: .statusWarning)
        case .cancelled: DetailTag(text: "Cancelled", symbol: "xmark")
        }
    }
}
