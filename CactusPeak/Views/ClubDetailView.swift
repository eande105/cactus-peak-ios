import SwiftUI
import MapKit

struct ClubDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dts
    let clubID: ClubID
    @State private var dayIdx = 0
    @State private var showsMap = false
    @State private var pendingHome: ClubID?
    @State private var titleHidden = false
    @State private var bookingHidden = false

    var body: some View {
        let club = model.club(clubID)
        let reading = model.busyness(club)
        List {
            HeroHeaderSection(height: 280) {
                mapHero(club)
            } content: {
                header(club, reading)
            }
            reserve(club)
            classes(club)
            crowd(club)
            hours(club)
            amenities(club)
            coaches(club)
            details(club)
            homeClub(club)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .heroPage(heroVisible: !titleHidden)
        .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        .modifier(ScreenChrome(club: club, titleHidden: titleHidden, bookingHidden: bookingHidden, showBook: { showBook(club.id, .classes) },
                               call: { call(club) }))
        .homeClubConfirmation($pendingHome)
        .sheet(isPresented: $showsMap) { ClubMapSheet(club: club) }
    }

    /// Sets the current club and the Book segment, then goes to the Book tab.
    private func showBook(_ id: ClubID, _ segment: BookSegment, day: Date? = nil) {
        ClubActions.showBook(id, segment, day: day, model: model, router: router)
    }
}

/// What a club page shows around its list as a pushed screen: the title, Book (once the intro button scrolls away) and favourite.
private struct ScreenChrome: ViewModifier {
    @Environment(AppModel.self) private var model
    let club: Club
    let titleHidden: Bool
    let bookingHidden: Bool
    let showBook: () -> Void
    let call: () -> Void

    func body(content: Content) -> some View {
        content
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(club.shortName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailBarTitle(title: club.shortName, shown: titleHidden)
            }
            if bookingHidden {
                ToolbarItem(placement: .topBarTrailing) { DetailBarButton(title: "Book", action: showBook) }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            // Call and Share are less frequent than Directions and Book, so they wait in the overflow menu, as the
            // less common actions do on a Maps place card.
            ToolbarOverflowMenu {
                Button("Call \(club.phone)", systemImage: "phone", action: call)
                ShareLink(item: URL(string: "https://app.cactuspeak.example/clubs/\(club.slug)")!, subject: Text(club.fullName)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.toggleFavourite(club: club.id) } label: { Image(systemName: model.favouriteClubs.contains(club.id) ? "heart.fill" : "heart") }
                    .barItem()
                    .accessibilityLabel(model.favouriteClubs.contains(club.id) ? "Remove favourite" : "Favourite")
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

/// Club actions shared by the club page and its map sheet.
enum ClubActions {
    /// Sets the current club and the Book segment, then goes to the Book tab.
    @MainActor static func showBook(_ id: ClubID, _ segment: BookSegment, day: Date? = nil, model: AppModel, router: AppRouter) {
        model.currentClubID = id
        router.segment = segment
        let c = model.club(id)
        if c.courts(for: router.sport) == 0, let sp = c.courtSports.first { router.sport = sp }
        if let day { router.day = day }
        router.selection = .book
        router.paths[.book] = []
    }
    @MainActor static func directionsURL(_ c: Club) -> URL? {
        URL(string: "http://maps.apple.com/?daddr=\(c.latitude),\(c.longitude)&q=\(c.fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
}

extension ClubDetailView {

    private func openMaps(_ c: Club) {
        if let u = ClubActions.directionsURL(c) { openURL(u) }
    }

    private func call(_ c: Club) {
        if let u = URL(string: "tel:\(c.phone.filter(\.isNumber))") { openURL(u) }
    }

    /// The club on a map, as the top of a Maps place card. A tap opens the full map.
    private func mapHero(_ c: Club) -> some View {
        Button { showsMap = true } label: {
            // The centre sits a little north of the club, so the pin shows below the bar's buttons.
            let center = CLLocationCoordinate2D(latitude: c.coordinate.latitude + 0.0016, longitude: c.coordinate.longitude)
            Map(initialPosition: .camera(MapCamera(centerCoordinate: center, distance: 2200)), interactionModes: []) {
                Marker(c.shortName, image: "RibPeakMark", coordinate: c.coordinate).tint(Color.brandAccent)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            // The map takes no touches, so the hero needs its own tap area.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map of \(c.fullName)")
        .accessibilityHint("Opens a full map")
    }

    /// The name and city, then the three things people check before they go (open, how far, how busy), as the
    /// header strip of a Maps place card, then Book and Directions.
    private func header(_ c: Club, _ r: BusynessReading) -> some View {
        let open = c.isOpen(at: model.now)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.fullName)
                    .brandFont(.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .onScrollVisibilityChange(threshold: 0.2) { titleHidden = !$0 }
                // The name is the cross streets, so the city has its own line. At accessibility sizes the home
                // club tag takes a line of its own.
                let ax = dts.isAccessibilitySize
                (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))) {
                    Text("\(c.city), AZ")
                    if c.id == model.member.homeClubID {
                        if !ax { Text("·") }
                        Label("Home club", systemImage: "house.fill").labelStyle(.titleAndIcon).foregroundStyle(Color.linkText)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            // An explicit colour for the text only: inside a header, the hierarchical `.primary` resolves to
            // secondary. The buttons keep the colours their styles give them.
            .foregroundStyle(Color.primary)
            Divider()
            DetailStatStrip {
                DetailStat(label: "Hours", detail: open ? "until \(c.openUntilText(on: model.now))" : "opens \(c.opensText(model.now))") {
                    Text(open ? "Open" : "Closed").brandFont(.numeral(.small)).foregroundStyle(open ? Color.statusSuccess : Color.secondary)
                }
                DetailStat(label: "Distance", number: String(format: "%.1f", c.distanceMiles), detail: "miles")
                DetailStat(label: "Crowd", detail: r.closed ? "Closed" : "\(r.word) now") {
                    RibMeter(value: r.closed ? 0 : r.level, tone: .crowd(r.level), size: .md, peak: false)
                }
            }
            .foregroundStyle(Color.primary)
            Divider()
            // Side by side, or stacked at accessibility sizes so each label fits on its own line.
            (dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                Button { showBook(c.id, .classes) } label: { Text("Book here").frame(maxWidth: .infinity) }
                    .accentProminent()
                Button { openMaps(c) } label: {
                    // The glyph takes room the word needs at accessibility sizes.
                    Group {
                        if dts.isAccessibilitySize { Text("Directions") }
                        else { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    }
                    .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.glass)
                    .tint(Color.linkText)
            }
            .controlSize(.large)
            .buttonBorderShape(dts.isAccessibilitySize ? .roundedRectangle(radius: DetailMetrics.cornerRadius) : .capsule)
            .fontWeight(.semibold)
            .reportsHidden($bookingHidden)
        }
    }

    /// The crowd by hour, for today or another day this week, then each area. The header strip shows the reading now.
    private func crowd(_ c: Club) -> some View {
        let day = model.now.startOfAZDay.addingDays(dayIdx)
        return Section {
            if dts.isAccessibilitySize {
                Picker("Day", selection: $dayIdx) { ForEach(0..<7, id: \.self) { Text(model.now.startOfAZDay.addingDays($0).cpFormat("EEEE")).tag($0) } }.pickerStyle(.menu)
            } else {
                Picker("Day", selection: $dayIdx) {
                    ForEach(0..<7, id: \.self) { i in Text(i == 0 ? "Today" : model.now.startOfAZDay.addingDays(i).cpFormat("EEE")).tag(i).accessibilityLabel(model.now.startOfAZDay.addingDays(i).cpFormat("EEEE")) }
                }.pickerStyle(.segmented)
            }
            PopularTimesChart(values: model.popular(c, day: day), nowHour: dayIdx == 0 ? AZ.cal.component(.hour, from: model.now) : nil, compact: false)
            ForEach(model.areas(c)) { AreaCrowdRow(area: $0) }
        } header: {
            DetailSectionHeader(title: "Crowd")
        } footer: {
            Text(model.popularCaption(c))
        }
    }

    @ViewBuilder private func reserve(_ c: Club) -> some View {
        let rows: [(String, ReserveKind)] = [
            c.hasCourts ? ("figure.pickleball", .court) : nil,
            c.hasPool ? ("figure.pool.swim", .lane) : nil,
            c.hasKids ? ("face.smiling", .kidsClub) : nil,
        ].compactMap { $0 }
        Section {
            if rows.isEmpty {
                Text("\(c.area) has no pool, courts or kids club.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.1) { r in
                let line = model.nextOpenLine(r.1, club: c).map { $0.replacingOccurrences(of: "\(r.1.title) · ", with: "") }
                Button { showBook(c.id, r.1.segment) } label: {
                    DetailFactRow(symbol: r.0, text: r.1.title, secondary: line) { RowPill(text: "Book") }
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .accessibilityElement(children: .combine)
            }
        } header: {
            DetailSectionHeader(title: "Reserve")
        }
    }

    /// The week's hours as a table, today first and in bold, as a Maps place card lists them.
    private func hours(_ c: Club) -> some View {
        Section {
            HoursTable(club: c, now: model.now)
            DetailFactRow(symbol: "person.crop.circle.badge.checkmark", text: "Desk staffed 6 am to 8 pm")
        } header: {
            DetailSectionHeader(title: "Hours") { router.present(.hours(c.id)) }
        }
    }

    private func amenities(_ c: Club) -> some View {
        let spaces = c.spaces
        return Section {
            ForEach(spaces.primary) { s in
                HStack(spacing: 12) {
                    SpaceGraphic(id: s.graphic).frame(width: 32, height: 32).accessibilityHidden(true)
                    Text(s.name).font(.headline)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(spaces.amenities) { a in
                HStack(spacing: 12) {
                    SpaceGraphic(id: a.graphic).frame(width: 32, height: 32).accessibilityHidden(true)
                    Text(a.name)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            DetailSectionHeader(title: "Amenities")
        } footer: {
            if !c.hasPool { Text("No pool.") }
        }
    }

    @ViewBuilder private func classes(_ c: Club) -> some View {
        let list = model.sessions(club: c.id, day: model.now).filter { $0.start > model.now }.prefix(6)
        Section {
            if list.isEmpty { Text("No more classes today.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(list)) { s in
                NavigationLink(value: AppRoute.classSession(s.id)) {
                    ClassRow(data: model.rowData(s), onAction: { ClassActions.primary(s, model: model, router: router) })
                }
                .navigationLinkIndicatorVisibility(.hidden)
            }
        } header: {
            DetailSectionHeader(title: "Classes today", detail: list.isEmpty ? nil : "\(list.count) more today") {
                showBook(c.id, .classes, day: model.now.startOfAZDay)
            }
        }
    }

    @ViewBuilder private func coaches(_ c: Club) -> some View {
        let list = model.coaches.filter { $0.clubs.contains(c.id) }
        if !list.isEmpty {
            CardStripSection(items: list, count: 5, span: 2) {
                DetailSectionHeader(title: "Coaches", detail: "\(list.count) coaches") { router.push(.coachList(c.id)) }
            } card: { co in
                Button { router.push(.coach(co.id)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        CoachImage(name: co.fullName, category: co.category, size: 56)
                        Text(co.shortName).font(.headline).lineLimit(1)
                        Text(co.credential).font(.footnote).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Where it is and how to reach it, as the Details section at the end of a Maps place card.
    private func details(_ c: Club) -> some View {
        Section {
            Button { showsMap = true } label: {
                DetailFactRow(symbol: "mappin.and.ellipse", text: c.address, secondary: String(format: "%.1f mi away", c.distanceMiles))
            }
            .foregroundStyle(.primary)
            .accessibilityHint("Opens a full map")
            Button { call(c) } label: { DetailFactRow(symbol: "phone", text: c.phone) }
                .foregroundStyle(.primary)
                .accessibilityLabel("Call \(c.phone)")
        } header: {
            DetailSectionHeader(title: "Details")
        }
    }

    private func homeClub(_ c: Club) -> some View {
        Section {
            Button {
                if c.id != model.member.homeClubID { if model.canChangeHomeClub { pendingHome = c.id } else { model.showToast("Changed this cycle. Next change after \(model.nextBillDate.cpDayMonth).") } }
            } label: {
                Label("Set as home club", systemImage: c.id == model.member.homeClubID ? "checkmark.circle.fill" : "house")
            }
            .disabled(model.isTeen)
        } footer: {
            if model.member.plan == .trailhead { Text("You can change your home club once per billing cycle.") }
        }
    }
}

/// The club's map at full height: pan and zoom, the system map controls, and Directions.
private struct ClubMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let club: Club
    @State private var camera: MapCameraPosition

    init(club: Club) {
        self.club = club
        _camera = State(initialValue: .region(MKCoordinateRegion(center: club.coordinate, span: .init(latitudeDelta: 0.03, longitudeDelta: 0.03))))
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                Marker(club.shortName, image: "RibPeakMark", coordinate: club.coordinate).tint(Color.brandAccent)
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(club.shortName)
            .navigationSubtitle(club.address)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() }.barItem() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        if let u = ClubActions.directionsURL(club) { openURL(u) }
                    }
                    .barItem()
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct ClubClassesView: View {
    let clubID: ClubID
    var body: some View { ClubDetailView(clubID: clubID) }
}

/// One confirmation for a home club change, used by club detail and Settings.
struct HomeClubConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var pending: ClubID?
    func body(content: Content) -> some View {
        content.confirmationDialog(pending.map { "Set \(model.club($0).fullName) as your home club?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Set as home club") { if let id = pending { model.setHomeClub(id) }; pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { if model.member.plan == .trailhead { Text("You can change your home club once per billing cycle.") } }
    }
}

extension View {
    func homeClubConfirmation(_ pending: Binding<ClubID?>) -> some View { modifier(HomeClubConfirmation(pending: pending)) }
}

// MARK: - Coaches

struct CoachListView: View {
    @Environment(AppModel.self) private var model
    let clubID: ClubID?
    var body: some View {
        let list = model.coaches.filter { clubID == nil || $0.clubs.contains(clubID!) }
        List(list) { c in
            NavigationLink(value: AppRoute.coach(c.id)) { CoachCard(coach: c) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(clubID.map { model.club($0).shortName + " coaches" } ?? "Coaches").navigationBarTitleDisplayMode(.inline)
    }
}

/// A coach's page, laid out like the class page: the portrait, the name and credential, the discipline tags, then
/// Book a session (when they train), the action buttons, their classes this week as Calendar-style date rows, About,
/// clubs, and personal training prices as an App Store-style strip.
struct CoachProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    let coachID: CoachID
    @State private var titleHidden = false
    @State private var bookingHidden = false

    var body: some View {
        let c = model.coach(coachID)
        let classes = model.sessions.filter { $0.coachID == c.id && $0.start > model.now && $0.start < model.now.addingDays(7) && model.visible($0) }
        List {
            DetailHeaderSection {
                intro(c)
                if c.trains {
                    DetailPrimaryButton(title: bookTitle) { router.present(.ptPicker(c.id)) }
                        .reportsHidden($bookingHidden)
                }
                actions(c, hasClasses: !classes.isEmpty)
            }
            thisWeek(c, classes: classes)
            Section {
                Text(c.bio)
            } header: { DetailSectionHeader(title: "About") }
            Section {
                ForEach(c.clubs, id: \.self) { id in
                    let club = model.club(id)
                    NavigationLink(value: AppRoute.club(id)) {
                        DetailFactRow(symbol: "mappin.and.ellipse", text: club.fullName, secondary: "\(club.city), AZ")
                    }
                }
            } header: { DetailSectionHeader(title: c.clubs.count == 1 ? "Club" : "Clubs") }
            if c.trains { training }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationBarTitleDisplayMode(.inline).navigationTitle(c.shortName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailBarTitle(title: c.fullName, shown: titleHidden)
            }
            if c.trains && bookingHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailBarButton(title: model.isTeen ? "Ask" : "Book") { router.present(.ptPicker(c.id)) }
                }
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    private var bookTitle: String {
        model.isTeen ? "Ask \(model.member.ownerFirst) to approve" : (model.member.plan == .summit ? "Book intro session" : "Book a session")
    }

    // MARK: Intro and actions

    /// The portrait, the name, the credential, then the discipline and specialty tags, as the class page shows its tags.
    private func intro(_ c: Coach) -> some View {
        DetailIntro(title: c.fullName, titleHidden: $titleHidden) {
            CoachImage(name: c.fullName, category: c.category, size: 96)
        } lines: {
            Text(c.credential).font(.subheadline).foregroundStyle(.secondary)
        } facts: {
            tags(c)
        }
    }

    @ViewBuilder private func tags(_ c: Coach) -> some View {
        // A specialty that only repeats the discipline adds nothing.
        let extra = c.specialties.filter { $0.caseInsensitiveCompare(c.category.title) != .orderedSame }
        let items = Group {
            CategoryBadge(category: c.category)
            if c.trains { DetailTag(text: "Personal training", symbol: "figure.strengthtraining.traditional", tint: .statusSuccess) }
            ForEach(extra, id: \.self) { DetailTag(text: $0) }
        }
        if dts.isAccessibilitySize {
            FlowLayout(spacing: 6) { items }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { items }
                FlowLayout(spacing: 6) { items }
            }
        }
    }

    /// Their classes on the Book page, then share, as the class page's equal buttons.
    private func actions(_ c: Coach, hasClasses: Bool) -> some View {
        DetailActionRow {
            if hasClasses {
                Button { showSchedule(c) } label: { DetailActionLabel(title: "Schedule", symbol: "calendar") }
                    .accessibilityLabel("Show \(c.shortName)'s classes on the schedule")
            }
            ShareLink(item: URL(string: "https://app.cactuspeak.example/coaches/\(c.id)")!, subject: Text(c.fullName)) {
                DetailActionLabel(title: "Share", symbol: "square.and.arrow.up")
            }
        }
    }

    private func showSchedule(_ c: Coach) {
        router.segment = .classes
        router.filters.coachID = c.id
        router.selection = .book
    }

    // MARK: This week

    /// Up to five classes as Calendar lists events: a date leaf, the class and time, and the spots left. The header
    /// opens the full week on the Book page.
    @ViewBuilder private func thisWeek(_ c: Coach, classes: [ClassSession]) -> some View {
        if classes.isEmpty {
            Section {
                Text("\(c.shortName.replacingOccurrences(of: ".", with: "")) has no classes this week.").foregroundStyle(.secondary)
            } header: { DetailSectionHeader(title: "This week") }
        } else {
            Section {
                ForEach(classes.prefix(5)) { s in
                    let left = model.spotsLeft(s)
                    NavigationLink(value: AppRoute.classSession(s.id)) {
                        HStack(spacing: 12) {
                            DateBadge(date: s.start)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.headline)
                                Text([s.start.cpTimeShort, c.clubs.count > 1 ? model.club(s.clubID).shortName : ""]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
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
                DetailSectionHeader(title: "This week", detail: classes.count == 1 ? "1 class" : "\(classes.count) classes") { showSchedule(c) }
            }
        }
    }

    // MARK: Personal training

    /// The prices side by side, with the price for each session under each pack, then the rules as glyph rows.
    private var training: some View {
        Section {
            DetailStatStrip {
                DetailStat(label: "Single", number: "$75", detail: "1 session")
                DetailStat(label: "4 pack", number: "$276", detail: "$69 each")
                DetailStat(label: "8 pack", number: "$520", detail: "$65 each")
                DetailStat(label: "12 pack", number: "$732", detail: "$61 each")
            }
            .padding(.vertical, 6)
            if model.member.plan == .summit {
                DetailFactRow(symbol: "checkmark.seal", text: "1 intro session a quarter", secondary: "Included with Summit", tint: .statusSuccess)
            }
            DetailFactRow(symbol: "clock", text: "45 min sessions", secondary: model.member.plan == .summit ? "Intro sessions are 30 min" : nil)
            DetailFactRow(symbol: "arrow.uturn.backward", text: "Cancel or reschedule free", secondary: "Up to 24 hours before")
            DetailFactRow(symbol: "calendar", text: "Packs last 12 months", secondary: "They pause during a freeze")
        } header: {
            DetailSectionHeader(title: "Personal training")
        }
    }
}
