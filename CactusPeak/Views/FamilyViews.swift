import SwiftUI

struct FamilyView: View {
    /// Toolbar buttons zoom the sheets they open out of themselves (see `zoomSource`).
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var removePlan = false
    @State private var removeTarget: Person?

    var body: some View {
        List {
            Section {
                ForEach(model.people) { p in
                    NavigationLink(value: AppRoute.familyMember(p.id)) {
                        HStack(spacing: 12) {
                            Avatar(initials: String(p.first.prefix(1) + p.last.prefix(1)), category: nil, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.first == model.member.first && p.role != .admin ? "\(p.name) (you)" : p.name).font(.headline)
                                Text(p.invitePending ? "\(p.roleLabel) · Invite pending" : p.roleLabel).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 56).accessibilityElement(children: .combine)
                    }
                    .swipeActions { if p.role != .admin && model.isOwner { Button("Remove", role: .destructive) { removeTarget = p } } }
                    .swipeActions(edge: .leading) { if p.invitePending { Button("Remind") { model.showToast("Reminder sent to \(p.first).") }.tint(Color.brandAccent) } }
                    .contextMenu { if p.invitePending { Button("Send a reminder", systemImage: "bell") { model.showToast("Reminder sent to \(p.first).") } } }
                    .accessibilityAction(named: "Send a reminder") { if p.invitePending { model.showToast("Reminder sent to \(p.first).") } }
                }
                if model.isOwner { Button { router.present(.addFamily) } label: { Label("Add a family member", systemImage: "plus") } }
            } header: { DetailSectionHeader(title: "People", detail: model.people.count == 1 ? "1 person" : "\(model.people.count) people") } footer: { Text("Family add-ons: +$39 per adult, +$19 per child (6 months to 17). Same access as your plan. Kids club is included for children 12 and under. Teens 13 to 17 follow the teen rules.") }
            if model.isOwner {
                Section {
                    DetailFactRow(symbol: "creditcard", text: "Next bill $\(model.nextBillTotal).00", secondary: "\(model.nextBillDate.cpFormat("EEEE, MMM d")) · Managed by you")
                        .monospacedDigit()
                } header: { DetailSectionHeader(title: "Billing") }
                Section { Button("Remove family plan", role: .destructive) { removePlan = true } }
            } else {
                Section { Text("Ask \(model.member.ownerFirst) to change this.").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Family").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.present(.addFamily, zoomFrom: "family.add") } label: { Image(systemName: "plus") }.barItem().accessibilityLabel("Add member")
                }
                .zoomSource("family.add", in: zoomNamespace)
            }
        }
        .confirmationDialog("Remove \(removeTarget?.first ?? "this person") from the plan?", item: $removeTarget, titleVisibility: .visible) { p in
            Button("Remove from \(model.nextBillDate.cpDayMonth)", role: .destructive) { model.removePerson(p.id); model.showToast("\(p.first) is off the plan from \(model.nextBillDate.cpDayMonth).") }
        } message: { p in Text("\(p.first) keeps access until your next bill on \(model.nextBillDate.cpDayMonth).") }
        .confirmationDialog("Remove the family plan?", isPresented: $removePlan, titleVisibility: .visible) {
            Button("Remove family plan", role: .destructive) { for p in model.people where p.role != .admin { model.removePerson(p.id) } }
        } message: { Text("Everyone but you leaves the plan on \(model.nextBillDate.cpDayMonth).") }
    }
}

struct FamilyMemberView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let personID: PersonID
    @State private var confirmPause = false
    @State private var confirmRemove = false
    @State private var titleHidden = false

    var body: some View {
        if let p = model.people.first(where: { $0.id == personID }) {
            List {
                // A person, so the page leads like a contact card: the avatar, the name, then the role and club.
                DetailHeaderSection {
                    DetailIntro(title: p.name, titleHidden: $titleHidden) {
                        Avatar(initials: String(p.first.prefix(1) + p.last.prefix(1)), category: nil, size: 88)
                    } lines: {
                        Text("\(p.roleLabel) · \(model.homeClub.fullName)").font(.subheadline).foregroundStyle(.secondary)
                    } facts: {
                        HStack(spacing: 6) {
                            if p.invitePending { DetailTag(text: "Invite pending", symbol: "envelope") }
                            if p.accessPaused { DetailTag(text: "Access paused", symbol: "pause.fill", tint: .statusWarning) }
                        }
                    }
                    DetailActionRow {
                        NavigationLink(value: AppRoute.myBookings) { DetailActionLabel(title: "Bookings", symbol: "ticket") }
                        Button { router.present(.pass) } label: { DetailActionLabel(title: "Pass", symbol: "qrcode") }
                            .accessibilityLabel(p.role == .teen ? "Show \(p.first)'s pass" : "Show pass for kids club")
                    }
                }
                if p.role == .teen {
                    Section {
                        toggle("Courts", p, \.courtsAllowed)
                        toggle("Lap lanes (from age 14)", p, \.lanesAllowed, shown: p.lanesAllowed && p.age >= 14).disabled(p.age < 14)
                        toggle("Tell me when \(p.first) checks in", p, \.checkInAlerts)
                    } header: { Text("Parent controls") } footer: {
                        Text("Personal training needs a parent's OK. Approvals arrive in your Inbox.")
                    }.disabled(!model.isOwner)
                    Section {
                        Label("Teen OK classes only: all Youth classes plus selected others, such as Teen Strength and Mind & Body.", systemImage: "checkmark.shield")
                    }
                    if model.isOwner, p.age == 17 { Section { Text("\(p.first) turns 18 soon. We'll move \(p.first) to the adult add-on, +$39/mo, with 30 days' notice.") } }
                    if !model.isOwner { Section { Text("Ask \(model.member.ownerFirst) to change this.").foregroundStyle(.secondary) } }
                } else if p.role == .child {
                    Section {
                        Label("Kids club is included. You check in at the same club.", systemImage: "face.smiling")
                        TextField("Allergies and notes", text: Binding(get: { p.allergies }, set: { var q = p; q.allergies = $0; model.updatePerson(q) }))
                    }
                }
                if model.isOwner, p.role != .admin {
                    Section {
                        if p.role == .teen { Button(p.accessPaused ? "Resume \(p.first)'s access" : "Pause \(p.first)'s access") { confirmPause = true } }
                        Button("Remove from plan", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle(p.first).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { DetailBarTitle(title: p.name, shown: titleHidden) } }
            .confirmationDialog("Pause \(p.first)'s access?", isPresented: $confirmPause, titleVisibility: .visible) {
                Button(p.accessPaused ? "Resume access" : "Pause access", role: .destructive) { var q = p; q.accessPaused.toggle(); model.updatePerson(q) }
            }
            .confirmationDialog("Remove \(p.first)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove from \(model.nextBillDate.cpDayMonth)", role: .destructive) { model.removePerson(p.id); router.goBack() }
            } message: { Text("\(p.first) keeps access until your next bill on \(model.nextBillDate.cpDayMonth).") }
        } else {
            ContentUnavailableView("Person not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
    /// Binds a Person flag straight to `updatePerson`. The key path avoids passing a non-Sendable closure into `Binding`.
    private func toggle(_ title: String, _ p: Person, _ keyPath: WritableKeyPath<Person, Bool>, shown: Bool? = nil) -> some View {
        Toggle(title, isOn: Binding(get: { shown ?? p[keyPath: keyPath] }, set: { var q = p; q[keyPath: keyPath] = $0; model.updatePerson(q) })).frame(minHeight: 44)
    }
}

// MARK: - Guest passes

struct GuestPassesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var body: some View {
        Group {
            if model.member.plan.guestPassesPerMonth == 0 {
                EmptyState(title: "Guest passes come with Ridge", message: "Ridge includes 1 guest pass a month.", symbol: "person.badge.plus", actionTitle: "See plans") { router.paths[.you] = [.membership, .plans] }
                    .screenBackground()
            } else {
                List {
                // The count is the page's answer, so it leads, large, with the share button under it, as a Wallet
                // pass leads with its balance.
                Section {
                    VStack(spacing: 6) {
                        Text("\(model.guestPassesLeft)").brandFont(.numeral(.hero))
                        Text(model.guestPassesLeft == 1 ? "guest pass left" : "guest passes left").font(.headline)
                        Text("\(model.member.plan.guestPassesPerMonth) a month · resets \(model.nextBillDate.cpDayMonth)")
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
                // The button stands on the page under the count card, not inside it.
                Section {
                    if model.guestPassesLeft > 0 {
                        Button { router.present(.guestShare) } label: { Label("Share a guest pass", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            .accentProminent().controlSize(.large)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    } else {
                        Button { } label: { Label("Buy a day pass for a friend, $20", systemImage: "ticket").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass).controlSize(.large)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                } footer: { Text("Passes do not roll over. A pass is good for 14 days from the day you send it: one visit, one club. Guests must be 18 or older, or 16 to 17 with a guardian waiver.") }
                if !model.guestPasses.isEmpty {
                    Section {
                        ForEach(model.guestPasses) { g in
                            HStack {
                                VStack(alignment: .leading) { Text(g.guest).font(.headline); Text("Expires \(g.expires.cpDayMonth)").font(.subheadline).foregroundStyle(.secondary) }
                                Spacer()
                                // An HStack, not a Label: inside a list row a Label takes the row's wide icon spacing.
                                HStack(spacing: 4) {
                                    Image(systemName: g.status == .used ? "checkmark.circle.fill" : (g.status == .expired ? "clock" : "paperplane.fill")).imageScale(.small)
                                    Text(g.status.rawValue)
                                }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(g.status == .used ? Color.statusSuccess : Color.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .swipeActions { Button("Revoke", role: .destructive) { model.revokeGuestPass(g.id) } }
                            .contextMenu { Button("Revoke", role: .destructive) { model.revokeGuestPass(g.id) } }
                            .accessibilityAction(named: "Revoke") { model.revokeGuestPass(g.id) }
                        }
                    } header: { DetailSectionHeader(title: "Shared passes") }
                }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Guest passes").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProgressRibs2: View {
    var left: Int; var total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: 3).fill(i < left ? Color.brandSecondary : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.borderStrong, lineWidth: 1.5)).frame(width: 10, height: 22)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(left) of \(total) guest passes left")
    }
}

// MARK: - Inbox

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts
    @State private var filter = "All"

    var body: some View {
        let list = model.inbox.filter { i in
            switch filter {
            case "Bookings": i.kind == .waitlist || i.kind == .reminder
            case "Club": i.kind == .club
            case "Billing": i.kind == .billing
            case "Family": i.kind == .family || i.kind == .approval
            default: true
            }
        }
        List {
            if !model.notificationsAuthorized {
                Section { Banner(tone: .warning, text: "Alerts are off. Turn on alerts so you do not miss a waitlist spot.", actionTitle: "Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            let today = list.filter { AZ.cal.isDate($0.time, inSameDayAs: model.now) }
            let earlier = list.filter { !AZ.cal.isDate($0.time, inSameDayAs: model.now) }
            if !today.isEmpty { Section("Today") { ForEach(today) { row($0) } } }
            if !earlier.isEmpty { Section("Earlier") { ForEach(earlier) { row($0) } } }
        }
        .listStyle(.insetGrouped)
        .overlay { if list.isEmpty { EmptyState(title: "You're all caught up", message: "Waitlist spots and reminders show here.", symbol: "bell.slash").background(Color(.systemGroupedBackground)) } }
        .navigationTitle("Inbox").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) { ForEach(["All", "Bookings", "Club", "Billing", "Family"], id: \.self) { Text($0).tag($0) } }
                    Button("Mark all read") { model.markAllRead() }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.barItem().accessibilityLabel("Filter and mark read")
            }
        }
    }

    private func symbol(_ k: InboxItem.Kind) -> (String, ClassCategory?) {
        switch k {
        case .waitlist: ("bell.badge", .strength)
        case .reminder: ("alarm", .cycle)
        case .club: ("sun.max", .aqua)
        case .billing: ("creditcard", nil)
        case .family: ("person.2", .youth)
        case .coach: ("figure.strengthtraining.traditional", .strength)
        case .approval: ("checkmark.seal", .youth)
        }
    }

    private func row(_ i: InboxItem) -> some View {
        let (sym, cat) = symbol(i.kind)
        return Button {
            model.markRead(i.id)
            if let r = i.route, let u = URL(string: "cactuspeak://" + r.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) { router.open(u) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack { Circle().fill(cat.map { $0.color.opacity(0.16) } ?? Color(.tertiarySystemFill)); Image(systemName: sym).foregroundStyle(cat?.textColor ?? Color.secondary) }.frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if i.unread { Circle().fill(Color.brandAccent).frame(width: 8, height: 8).accessibilityHidden(true) }
                        Text(i.title).font(.headline)
                    }
                    Text(i.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(dts.isAccessibilitySize ? 3 : 2)
                    if i.kind == .waitlist, let h = model.activeHold, i.title.contains(h.title) {
                        BookingStateButton(state: .hold(h.holdExpires ?? model.now), action: { if model.confirmHold(h.id) { model.announceBooked(model.booking(h.id)) } }).padding(.top, 4)
                    }
                    Text(relative(i.time)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { model.deleteInbox(i.id) } }
        .swipeActions(edge: .leading) { Button(i.unread ? "Read" : "Unread") { model.markRead(i.id, i.unread) }.tint(Color.brandSecondary) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(i.unread ? "Unread. " : "")\(i.title). \(i.body). \(relative(i.time))")
    }

    private func relative(_ d: Date) -> String {
        let m = Int(model.now.timeIntervalSince(d) / 60)
        if m < 1 { return "Just now" }
        if m < 60 { return "\(m) min ago" }
        if m < 1440 { return d.cpTimeShort }
        return d.cpFormat("EEE MMM d")
    }
}
