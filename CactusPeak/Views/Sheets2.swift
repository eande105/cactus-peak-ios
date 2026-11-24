import SwiftUI
import PhotosUI

// MARK: - Filters

struct FiltersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        let count = liveCount([model.currentClubID])
        NavigationStack {
            Form {
                Section("Category") {
                    ForEach(ClassCategory.allCases) { c in
                        Toggle(isOn: Binding(get: { router.filters.categories.contains(c) }, set: { _ in toggle(c) })) {
                            Label { Text(c.title) } icon: { Image(systemName: c.symbol).foregroundStyle(c.textColor) }
                        }
                    }
                }
                Section("Time of day") {
                    ForEach(TimeOfDay.allCases) { t in
                        Toggle(isOn: Binding(get: { router.filters.times.contains(t) }, set: { on in if on { router.filters.times.insert(t) } else { router.filters.times.remove(t) } })) {
                            VStack(alignment: .leading) { Text(t.rawValue); Text(t.detail).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    Picker("Intensity", selection: $router.filters.maxIntensity) {
                        ForEach(1...5, id: \.self) { Text("Up to \(Intensity.word($0))").tag($0) }
                    }
                }
                Section("Options") {
                    Toggle("Good for first-timers", isOn: $router.filters.firstTimers)
                    Toggle("Spots open only", isOn: $router.filters.spotsOnly)
                    Toggle("Bookings", isOn: $router.filters.myBookings)
                }
            }
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            // The match count moves to the subtitle so the toolbar holds two icons on the trailing edge:
            // reset, then the one prominent action that applies the filters and closes the sheet.
            .navigationSubtitle("\(count) \(count == 1 ? "class" : "classes")")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", systemImage: "arrow.counterclockwise") { router.filters = ScheduleFilters() }
                        .barItem()
                        .disabled(router.filters.activeCount == 0)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Show \(count) \(count == 1 ? "class" : "classes")", systemImage: "checkmark") { router.dismissSheet() }
                        .accentProminent()
                }
            }
        }
    }
    private func toggle(_ c: ClassCategory) {
        if router.filters.categories.contains(c) { router.filters.categories.remove(c) } else { router.filters.categories.insert(c) }
    }
    private func liveCount(_ ids: [ClubID]) -> Int {
        let f = router.filters
        return ids.flatMap { model.sessions(club: $0, day: router.day) }.filter { s in
            (f.categories.isEmpty || f.categories.contains(s.category)) && (f.times.isEmpty || f.times.contains(TimeOfDay.of(s.start)))
            && s.intensity <= f.maxIntensity && (!f.firstTimers || s.firstTimers) && (!f.spotsOnly || model.spotsLeft(s) > 0)
            && (!f.myBookings || model.booking(forSession: s.id) != nil)
        }.count
    }
}

// MARK: - Date picker

struct DatePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        let kind: ReserveKind = router.segment == .courts ? .court : .kidsClub
        let last = model.reserveDays(kind).last ?? model.now
        NavigationStack {
            DatePicker("Day", selection: $router.day, in: model.now.startOfAZDay...last, displayedComponents: .date)
                .datePickerStyle(.graphical).environment(\.timeZone, AZ.tz).environment(\.calendar, AZ.cal).padding(.horizontal, 8)
                .navigationTitle("Pick a day").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}

// MARK: - Guest share

struct GuestShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var name = ""
    @State private var created: GuestPass?
    @State private var copied = false
    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    let link = "https://app.cactuspeak.example/guest/\(created.id)"
                    Section {
                        Label("Pass sent", systemImage: "checkmark.circle.fill").brandFont(.section).foregroundStyle(Color.statusSuccess)
                        Text("\(created.guest.isEmpty ? "Your guest" : created.guest) has until \(created.expires.cpDayMonth) to use it.")
                    }
                    Section {
                        Text(link).codeFont(.footnote, weight: .regular).textSelection(.enabled)
                        Button { UIPasteboard.general.string = link; copied = true } label: { Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        ShareLink(item: "\(created.guest), here is your free visit to Cactus Peak Athletic. Sign the waiver and show this at the desk: \(link)") { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                } else {
                    Section {
                        TextField("Guest first name (optional)", text: $name)
                    } footer: {
                        Text("Valid 14 days from today (until \(model.now.startOfAZDay.addingDays(14).cpDayMonth)). One visit, one club. Guest must be 18 or older, or 16 to 17 with a guardian waiver.")
                    }
                    Section {
                        Button("Create guest link") { created = model.guestPasses.first ?? nil; model.shareGuestPass(name: name); created = model.guestPasses.first }
                            .primaryAction(full: true).disabled(model.guestPassesLeft == 0)
                    }.listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Guest pass").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if created == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() }.barItem() }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } }
                }
            }
            .sensoryFeedback(.success, trigger: created?.id)
        }
    }
}

// MARK: - Add family member

struct AddFamilySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @SceneStorage("fam.first") private var first = ""
    @SceneStorage("fam.last") private var last = ""
    @SceneStorage("fam.email") private var email = ""
    @SceneStorage("fam.adult") private var adult = false
    @State private var age = 9
    @State private var guardian = false
    @State private var confirmDiscard = false
    @State private var photo: PhotosPickerItem?

    private var dirty: Bool { !first.isEmpty || !last.isEmpty || !email.isEmpty }
    private var cost: Int { adult ? 39 : 19 }
    private var needsEmail: Bool { adult || age >= 13 }
    private var valid: Bool { !first.isEmpty && !last.isEmpty && (!needsEmail || email.contains("@")) && (adult || guardian) && (adult || age >= 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $adult) {
                        Text("Adult +$39/mo").tag(true)
                        Text("Child +$19/mo (6 months to 17)").tag(false)
                    }.pickerStyle(.inline).labelsHidden()
                }
                Section("Details") {
                    TextField("First name", text: $first).textContentType(.givenName)
                    TextField("Last name", text: $last).textContentType(.familyName)
                    if !adult { Stepper("Age \(age)", value: $age, in: 0...17) }
                    TextField(needsEmail ? "Email" : "Email (optional)", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Add a photo", systemImage: "photo") }
                    if !adult && age < 1 { Text("Kids club starts at 6 months.").font(.footnote).foregroundStyle(Color.statusWarning) }
                    if !adult && age >= 13 { Text("\(first.isEmpty ? "They" : first) can use the app and check in. You manage billing.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Text("+$\(cost)/mo from your next bill on \(model.nextBillDate.cpDayMonth).")
                    if !adult { Toggle("I am this child's parent or guardian.", isOn: $guardian) }
                } footer: { Text("The invite link is valid for 7 days.") }
            }
            .navigationTitle("Add member").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(dirty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmDiscard = true } else { router.dismissSheet() } }.barItem() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(adult || age >= 13 ? "Send invite" : "Add") {
                        model.addPerson(first: first, last: last, adult: adult, age: adult ? 30 : age)
                        first = ""; last = ""; email = ""
                        router.dismissSheet()
                    }.disabled(!valid)
                }
            }
            .confirmationDialog("Discard this member?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { first = ""; last = ""; email = ""; router.dismissSheet() }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }
}

// MARK: - Plans

struct ComparePlansSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    private let rows: [(String, [String])] = [
        ("Clubs", ["Home club", "All 5", "All 5"]),
        ("Group classes", ["Every class at your club", "Every class at all 5", "Every class at all 5"]),
        ("Pools", ["At your club, if it has one", "All 3 pools", "All 3 pools"]),
        ("Courts", ["Not included", "At 3 clubs, 3 days ahead", "At 3 clubs, 3 days ahead"]),
        ("Recovery suite or lounge", ["Not included", "Not included", "At 4 clubs"]),
        ("Class booking window", ["7 days", "7 days", "9 days"]),
        ("Guest passes", ["Not included", "1 a month", "4 a month"]),
        ("Towel service", ["Not included", "Not included", "Included"]),
        ("PT intro session", ["Not included", "Not included", "1 a quarter"]),
    ]
    var body: some View {
        NavigationStack {
            Group {
                if dts.isAccessibilitySize {
                    List {
                        ForEach(Array(PlanTier.allCases.enumerated()), id: \.element) { i, p in
                            Section(p.name) { ForEach(rows, id: \.0) { r in LabeledContent(r.0, value: r.1[i]) } }
                        }
                    }
                } else {
                    ScrollView {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                ForEach(PlanTier.allCases) { p in
                                    VStack(alignment: .leading) { Text(p.name).font(.subheadline.weight(.bold)); Text("$\(p.price)/mo").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                                }
                            }
                            Divider().gridCellColumns(4)
                            ForEach(rows, id: \.0) { r in
                                GridRow(alignment: .top) {
                                    Text(r.0).font(.footnote.weight(.semibold))
                                    ForEach(0..<3, id: \.self) { i in
                                        let v = r.1[i]
                                        HStack(alignment: .top, spacing: 3) {
                                            Image(systemName: v == "Not included" ? "minus" : "checkmark").font(.caption2.weight(.bold)).foregroundStyle(v == "Not included" ? Color.secondary : Color.statusSuccess).padding(.top, 3)
                                            Text(v).font(.caption).foregroundStyle(v == "Not included" ? Color.secondary : Color.primary)
                                        }
                                    }
                                }
                                .padding(.vertical, 10)
                                Divider().gridCellColumns(4)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Compare plans").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}

struct PlanConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let plan: PlanTier
    var body: some View {
        let q = model.planQuote(to: plan)
        NavigationStack {
            Form {
                if q.isUpgrade {
                    Section {
                        LabeledContent("\(plan.name) from now", value: "$\(plan.price)/mo")
                        LabeledContent("Difference", value: "+$\(q.delta)/mo")
                        LabeledContent("Prorated by day for the rest of this cycle", value: "$\(q.proratedToday).00")
                        LabeledContent("Today's total") { Text("$\(q.proratedToday).00").fontWeight(.bold) }
                    } footer: {
                        Text("\(plan.name) starts today. From \(model.nextBillDate.cpDayMonth) your bill is $\(model.nextBillTotal + q.delta).00 a month.")
                    }
                    .monospacedDigit()
                } else {
                    Section { Text("Takes effect on your next billing date, \(q.effective.cpDayMonth).") }
                    if !q.lost.isEmpty {
                        Section("You lose") {
                            ForEach(q.lost, id: \.self) { Label($0, systemImage: "xmark.circle.fill").foregroundStyle(Color.statusDanger) }
                        }
                    }
                }
            }
            .navigationTitle(q.isUpgrade ? "Switch to \(plan.name)?" : "Move to \(plan.name)?").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() }.barItem() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(q.isUpgrade ? "Switch" : "Move") {
                        model.changePlan(to: plan); router.dismissSheet()
                        model.showToast(q.isUpgrade ? "You're on \(plan.name)." : "\(plan.name) starts \(q.effective.cpDayMonth).")
                    }
                }
            }
        }
    }
}

struct FreezeConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let months: Int
    var body: some View {
        let q = model.freezeQuote(months: months)
        NavigationStack {
            Form {
                Section { Text("Billing pauses until \(q.restart.cpDayMonth). You can't check in or book while frozen.") }
            }
            .navigationTitle("Freeze from \(q.start.cpDayMonth)?").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { router.dismissSheet() }.barItem() }
                ToolbarItem(placement: .confirmationAction) { Button("Freeze") { model.setFreeze(months: months); router.dismissSheet() } }
            }
        }
    }
}

// MARK: - PT picker

struct PTPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let coachID: CoachID
    @State private var day = AppModel.shared.now.startOfAZDay
    @State private var chosen: Date?
    @State private var message: String?
    var body: some View {
        let coach = model.coach(coachID)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) { InstructorChip(coach: coach, large: true); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brandAccent) }
                    Text("Available 8 am–8 pm").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ScrollView(.horizontal) {
                        HStack { ForEach(0..<7, id: \.self) { i in
                            let d = model.now.startOfAZDay.addingDays(i)
                            Button { day = d; chosen = nil } label: { AmenityChip(label: d.cpFormat("EEE d"), symbol: nil, isSelected: AZ.cal.isDate(d, inSameDayAs: day)) }.buttonStyle(.plain).frame(minHeight: 44)
                        } }
                    }.scrollIndicators(.hidden)
                }
                let slots = model.ptSlots(coach: coach, day: day)
                ForEach([("Morning", slots.filter { AZ.cal.component(.hour, from: $0.start) < 12 }), ("Afternoon and evening", slots.filter { AZ.cal.component(.hour, from: $0.start) >= 12 })], id: \.0) { g in
                    Section(g.0) {
                        ForEach(g.1) { s in
                            Button { if s.available { chosen = s.start } } label: {
                                HStack { Circle().fill(s.available ? Color.statusSuccess : Color(.tertiaryLabel)).frame(width: 8, height: 8).accessibilityHidden(true)
                                    Text(s.start.cpTimeShort).monospacedDigit().foregroundStyle(s.available ? Color.primary : Color.secondary)
                                    Spacer(); Text(s.available ? "Available" : "Booked").font(.footnote).foregroundStyle(.secondary)
                                    if chosen == s.start { Image(systemName: "checkmark").foregroundStyle(Color.brandAccent) } }
                                .frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!s.available).accessibilityAddTraits(chosen == s.start ? .isSelected : [])
                        }
                    }
                }
                Section {
                    if let message { Text(message).font(.subheadline) }
                    Text("Sessions are \(model.ptIntroAvailable ? "30 min for your Summit intro" : "45 min"). Free cancel or reschedule up to 24 hours before.").font(.footnote).foregroundStyle(.secondary)
                    Button(model.isTeen ? "Ask \(model.member.ownerFirst) to approve" : (model.ptIntroAvailable ? "Book intro session" : "Book session")) {
                        guard let chosen else { return }
                        switch model.bookPT(coach: coach, start: chosen) {
                        case .ok(let b): router.dismissSheet(); model.announceBooked(model.booking(b.id))
                        case .requestSent(let m): message = m
                        case .failed(let m): message = m
                        }
                    }.primaryAction(full: true).disabled(chosen == nil)
                }
            }
            .navigationTitle("Personal training").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { router.dismissSheet() }.barItem() } }
        }
    }
}

// MARK: - Profile, calendar, goal

struct EditProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var photo: PhotosPickerItem?
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section { PhotosPicker(selection: $photo, matching: .images) { Label("Change photo", systemImage: "camera") } }
                Section("Name") { TextField("First name", text: $model.member.first); TextField("Last name", text: $model.member.last) }
                Section("Contact") { TextField("Email", text: $model.member.email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }
            }
            .navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}

struct CalendarSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let bookingID: BookingID
    var body: some View {
        if let b = model.booking(bookingID) {
            let club = model.club(b.clubID)
            EventEditor(title: "\(b.title) · \(club.fullName)", location: club.address, start: b.start, end: b.end,
                        url: URL(string: "https://app.cactuspeak.example/book/class/\(b.sessionID ?? b.id)")) { saved in
                if saved { model.calendarAdded.insert(b.id); model.showToast("Added to calendar.") }
                router.dismissSheet()
            }
            .ignoresSafeArea()
        }
    }
}

struct GoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Stepper("\(model.weeklyGoal) visits a week", value: $model.weeklyGoal, in: 1...5)
                } footer: { Text("A streak week meets your goal. One rest week is forgiven per 10 weeks.") }
            }
            .navigationTitle("Weekly goal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.dismissSheet() } } }
        }
    }
}
