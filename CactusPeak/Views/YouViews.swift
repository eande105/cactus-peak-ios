import SwiftUI

struct YouView: View {
    /// Toolbar buttons zoom the sheets they open out of themselves (see `zoomSource`).
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        List {
            Section {
                Button { router.present(.editProfile) } label: {
                    (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))) {
                        Avatar(initials: String(model.member.first.prefix(1) + model.member.last.prefix(1)), category: nil, size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.member.name).brandFont(.section)
                            Text(profileLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 60).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Edit profile")
            }
            // The pass as a card, as Wallet shows a pass: the brand surface, the plan, the name and the number.
            // The whole card opens the full pass with its code.
            Section {
                Button { router.present(.pass) } label: { YouPassCard() }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.nightSurface)
                    .accessibilityLabel("Pass, \(model.member.plan.name), member number \(model.member.memberNumber.map { String($0) }.joined(separator: " "))")
                    .accessibilityHint("Shows the pass and its check-in code")
            }
            if model.isTeen {
                Section { Label("Your plan is managed by \(model.member.ownerFirst).", systemImage: "person.2").font(.subheadline) }
            }
            Section("Activity") {
                NavigationLink(value: AppRoute.progress) { row("Progress", "chart.bar", "\(model.streak.weeks)-week streak") }
            }
            if !model.isTeen {
                Section("Membership") {
                    NavigationLink(value: AppRoute.membership) { row("Membership", "creditcard", model.member.plan.name) }
                    NavigationLink(value: AppRoute.family) { row("Family", "person.2", "\(model.people.count) \(model.people.count == 1 ? "person" : "people")") }
                    NavigationLink(value: AppRoute.guestPasses) { row("Guest passes", "person.badge.plus", "\(model.guestPassesLeft) left") }
                }
            }
            Section("Support") {
                NavigationLink(value: AppRoute.notifications) { row("Inbox", model.unreadCount > 0 ? "bell.badge" : "bell", model.unreadCount > 0 ? "\(model.unreadCount) unread" : nil) }
                Link(destination: URL(string: "tel:4805550100")!) { row("Member services", "questionmark.circle", "(480) 555-0100") }
                Button { router.present(.feedback(model.pastBookings.first?.id ?? "")) } label: { row("Give feedback", "text.bubble", nil) }.buttonStyle(.plain)
            }
            Section { Text("Cactus Peak Athletic 1.0 (1)").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }.listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("You")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.present(.page(.settings), zoomFrom: "you.settings") } label: { Image(systemName: "gearshape") }.barItem().accessibilityLabel("Settings")
            }
            .zoomSource("you.settings", in: zoomNamespace)
        }
    }

    private var profileLine: String {
        model.member.isTeen ? "Teen · \(model.homeClub.fullName)" : "\(model.member.plan.name) · Since \(model.member.sinceText)"
    }

    /// One row style for every section: a secondary icon, the title, a trailing value.
    @ViewBuilder private func row(_ title: String, _ symbol: String, _ value: String?) -> some View {
        let label = Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
        if let value {
            LabeledContent { Text(value) } label: { label }.frame(minHeight: 44)
        } else {
            label.frame(minHeight: 44)
        }
    }
}

/// The You tab's pass: the logo and plan, the home club, and the number, on the night surface in both modes.
private struct YouPassCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image("LogoHorizontalReversed").resizable().scaledToFit().frame(height: 22).accessibilityHidden(true)
                Spacer()
                Text(model.member.plan.name).font(.footnote.weight(.bold)).foregroundStyle(Color.nightSurface)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Color.dawnCopper, in: Capsule())
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    // The profile row above names the member, so the pass names the home club.
                    Text(model.homeClub.fullName).brandFont(.title2).fixedSize(horizontal: false, vertical: true)
                    Text(model.member.memberNumber).codeFont(.subheadline).opacity(0.8)
                }
                Spacer(minLength: 12)
                Image(systemName: "qrcode").symbolFont(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.nightOnSurface.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.nightOnSurface)
        .padding(20)
        .contentShape(.rect)
    }
}

// MARK: - Membership

struct MembershipView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var unlocked = false
    @State private var walletAlert = false
    @State private var billingHistory = false
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        Group {
            if unlocked || !model.isOwner { content } else {
                ContentUnavailableView {
                    Label("Membership is locked", systemImage: "faceid")
                } description: { Text("Confirm it is you to see billing details.") } actions: {
                    Button("Unlock") { Task { unlocked = await BiometricGate.authenticate(reason: "Show billing details") } }.primaryAction()
                }
            }
        }
        .navigationTitle("Membership").navigationBarTitleDisplayMode(.inline)
        .task { if !unlocked { unlocked = await BiometricGate.authenticate(reason: "Show billing details") } }
    }

    // After the Apple Card page in Wallet: the plan as the first group, two summary tiles, then grouped lists.
    // The plan group uses the list's own row background, so the list clips nothing that the card draws.
    private var content: some View {
        let plan = model.member.plan
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    statusPill
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(plan.name).brandFont(.title).lineLimit(1)
                            Spacer(minLength: 8)
                            price(plan)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name).brandFont(.title)
                            price(plan)
                        }
                    }
                    Text(model.member.sinceText.isEmpty ? plan.tagline : "\(plan.tagline) · Member since \(model.member.sinceText)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            Section {
                (dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    // A button, not a NavigationLink: in a list row a link adds the row's own disclosure chevron.
                    Button { billingHistory = true } label: {
                        MembershipTile(title: "Next bill", value: "$\(model.nextBillTotal).00", detail: model.nextBillDate.cpFormat("EEE, MMM d"), link: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows billing history")
                    MembershipTile(title: "Payment", value: "Visa •• 4242", detail: "Billed on the \(Self.ordinal(model.member.billingDay))")
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let d = model.membershipCancelOn {
                Section { Banner(tone: .info, text: "Cancelling \(d.cpDayMonth). You keep full access until then.", actionTitle: "Reinstate") { model.reinstate() } }.listRowBackground(Color.clear)
            }
            if let (p, d) = model.pendingDowngrade {
                Section { Banner(tone: .info, text: "Moving to \(p.name) on \(d.cpDayMonth).", actionTitle: nil, action: nil) }.listRowBackground(Color.clear)
            }
            if model.paymentFailedDay > 0 {
                Section { Banner(tone: model.paymentFailedDay >= 8 ? .danger : .warning,
                                 text: model.paymentFailedDay >= 8 ? "New bookings are paused until you pay. Your pass still works. From day 15 the pass shows \"See the front desk\"." : "We could not charge your card. Retrying on day 3 and day 6. You have full access to day 7.",
                                 actionTitle: "Update payment") { model.paymentFailedDay = 0; model.showToast("Payment updated.") } }.listRowBackground(Color.clear)
            }
            Section {
                ForEach(plan.perks, id: \.self) { perk in
                    Label { Text(perk) } icon: { Image(systemName: "checkmark").foregroundStyle(Color.statusSuccess) }
                }
                NavigationLink(value: AppRoute.plans) { Text("Change plan").foregroundStyle(Color.linkText) }
            } header: { DetailSectionHeader(title: "Included") }
            Section {
                ForEach(model.billLines) { l in LabeledContent(l.label, value: "$\(l.amount).00") }
                LabeledContent { Text("$\(model.nextBillTotal).00").fontWeight(.semibold).foregroundStyle(Color.primary) } label: { Text("Total").fontWeight(.semibold) }
            } header: { DetailSectionHeader(title: "Next bill") }
            footer: { Text("$49 annual facility fee is charged in March.") }
            .monospacedDigit()
            Section {
                NavigationLink(value: AppRoute.billingHistory) { manageRow("Billing history", "clock.arrow.circlepath", nil) }
                if model.isFrozen { Button { model.resumeEarly() } label: { manageRow("Resume early", "play.circle", nil) } }
                NavigationLink(value: AppRoute.freeze) { manageRow(model.freeze == nil ? "Freeze membership" : "Freeze details", "pause.circle", nil) }
                NavigationLink(value: AppRoute.family) { manageRow("Family", "person.2", "\(model.people.count) \(model.people.count == 1 ? "person" : "people")") }
                // A link like its neighbours: it opens the coaches, where a pack is booked or bought.
                NavigationLink(value: AppRoute.coachList(nil)) {
                    manageRow("Personal training", "figure.strengthtraining.traditional", model.ptSessionsLeft > 0 ? "\(model.ptSessionsLeft) left" : "No packs")
                }
            } header: { DetailSectionHeader(title: "Manage") }
            Section {
                if model.walletAdded { Label("In Apple Wallet", systemImage: "checkmark.circle.fill") }
                else { WalletButton { walletAlert = true }.frame(height: 48) }
            }.listRowBackground(Color.clear)
            Section {
                NavigationLink(value: AppRoute.cancelMembership) { Text("Cancel membership").foregroundStyle(Color.statusDanger) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        // Before the household loads, the model holds empty defaults (billing day 1, plan price as the bill, no
        // join date). Show them as placeholders, not as facts.
        .readableWidth()
        .redacted(reason: model.householdLoaded ? [] : .placeholder)
        .allowsHitTesting(model.householdLoaded)
        .navigationDestination(isPresented: $billingHistory) { BillingHistoryView() }
        .alert("Wallet pass not available in this build", isPresented: $walletAlert) { Button("OK", role: .cancel) {} }
            message: { Text("A Wallet pass needs a signing certificate and a pass type ID.") }
    }

    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// One state for the membership. The banners below the tiles explain any state that is not active.
    @ViewBuilder private var statusPill: some View {
        if model.paymentFailedDay > 0 { StatusPill(text: "Payment failed", symbol: "exclamationmark.triangle.fill", tone: .danger) }
        else if model.isFrozen, let end = model.freeze?.end { StatusPill(text: "Frozen until \(end.cpDayMonth)", symbol: "pause.fill", tone: .neutral) }
        else if let d = model.membershipCancelOn { StatusPill(text: "Ends \(d.cpDayMonth)", symbol: "calendar.badge.exclamationmark", tone: .warning) }
        else { StatusPill(text: "Active", symbol: "checkmark", tone: .success) }
    }

    private func price(_ plan: PlanTier) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("$\(plan.price)").brandFont(.numeral(.large))
            Text("/mo").font(.subheadline).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    /// The You page row: a secondary glyph, the title and an optional trailing value.
    @ViewBuilder private func manageRow(_ title: String, _ symbol: String, _ value: String?) -> some View {
        let label = Label { Text(title).foregroundStyle(Color.primary) } icon: { Image(systemName: symbol).foregroundStyle(.secondary) }
        if let value { LabeledContent { Text(value) } label: { label } } else { label }
    }
}

/// A summary tile, as the Card Balance and Payment Due tiles on the Apple Card page: a label, the value, one fact.
/// The tile has the list's 26 pt continuous corner radius, so the row clip and the tile shape are the same.
private struct MembershipTile: View {
    var title: String
    var value: String
    var detail: String
    var link = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if link { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
            }
            Text(value).brandFont(.numeral(.small)).lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Charges as Wallet lists transactions: what it was and when on the leading side, the amount on the trailing side
/// in tabular figures, and the state in small text only when it is not paid.
struct BillingHistoryView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                charge("Next bill", date: model.nextBillDate.cpFormat("MMM d"), amount: model.nextBillTotal, state: "Upcoming")
            } header: { DetailSectionHeader(title: "Upcoming") }
            Section {
                ForEach(Array(model.billingHistory.enumerated()), id: \.offset) { _, r in
                    charge("\(model.member.plan.name) membership", date: r.0, amount: r.1, state: r.2 == "Paid" ? nil : r.2)
                }
            } header: { DetailSectionHeader(title: "Paid") }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Billing history").navigationBarTitleDisplayMode(.inline)
    }

    private func charge(_ title: String, date: String, amount: Int, state: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text([date, state].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("$\(amount).00").font(.headline).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plans

// After Edit Subscription in Settings: one group per plan, the name and price first, then what it includes. The
// current plan carries a checkmark, as a selected option does. The other plans end with the switch action.
struct PlansView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var body: some View {
        List {
            ForEach(PlanTier.allCases) { p in
                let current = p == model.member.plan
                let delta = p.price - model.member.plan.price
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).brandFont(.section)
                            Text(current ? "Current plan" : p == .ridge ? "Most popular" : p.tagline)
                                .font(.subheadline.weight(current || p == .ridge ? .semibold : .regular))
                                .foregroundStyle(current || p == .ridge ? Color.linkText : Color.secondary)
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("$\(p.price)").brandFont(.numeral(.medium))
                            Text("/mo").font(.footnote).foregroundStyle(.secondary)
                        }
                        if current {
                            Image(systemName: "checkmark.circle.fill").symbolFont(.title2.weight(.semibold)).foregroundStyle(Color.brandAccent).accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(current ? .isSelected : [])
                    ForEach(p.perks, id: \.self) { perk in
                        Label { Text(perk) } icon: { Image(systemName: "checkmark").foregroundStyle(Color.statusSuccess) }
                            .font(.subheadline)
                    }
                    if !current {
                        Button { router.present(.planConfirm(p)) } label: {
                            LabeledContent {
                                Text(delta > 0 ? "+$\(delta)/mo" : "−$\(abs(delta))/mo").monospacedDigit()
                            } label: {
                                Text("Switch to \(p.name)").foregroundStyle(Color.linkText).fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            Section {
                Button { router.present(.comparePlans) } label: { Label("Compare plans", systemImage: "tablecells") }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Family add-on +$39 per adult, +$19 per child (6 months to 17). Day pass $20.")
                    if model.member.plan == .trailhead {
                        Text(model.homeClubChangedThisCycle ? "Home club changed this cycle. Next change after \(model.nextBillDate.cpDayMonth)." : "Trailhead members can change home club once per billing cycle.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Plans").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Freeze

struct FreezeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var months = 2
    @State private var confirm = false
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        if let f = model.freeze { frozen(f) } else { form }
    }

    private var form: some View {
        let q = model.freezeQuote(months: months)
        let block = model.freezeBlockReason()
        return Form {
            // After Apple Fitness "Personalize Fitness and Health": the title and its line sit on the page, not in a card.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Freeze your membership").brandFont(.title).accessibilityAddTraits(.isHeader)
                    Text("Freeze for 1 to 3 months for $10/mo. The freeze covers everyone on your plan.")
                        .font(.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }
            if let block {
                Section { ContentUnavailableView("Freeze isn't available", systemImage: "pause.slash", description: Text(block)) }.listRowBackground(Color.clear)
            } else {
                Section {
                    if dts.isAccessibilitySize {
                        Picker("Length", selection: $months) { ForEach(1...3, id: \.self) { Text("\($0) month\($0 == 1 ? "" : "s")").tag($0) } }.pickerStyle(.menu)
                    } else {
                        Picker("Length", selection: $months) { ForEach(1...3, id: \.self) { Text("\($0) month\($0 == 1 ? "" : "s")").tag($0) } }.pickerStyle(.segmented)
                    }
                }
                Section {
                    LabeledContent("Starts", value: q.start.cpDayMonth)
                    LabeledContent("Ends", value: q.end.cpDayMonth)
                    LabeledContent("Billing restarts", value: q.restart.cpDayMonth)
                    LabeledContent("Cost", value: "$10/mo · $\(q.total) total")
                } header: { Text("Dates") } footer: { Text("The freeze starts on your first billing date at least 30 days from today.") }
                Section {
                    if q.affected.isEmpty { Label("No bookings fall inside the freeze", systemImage: "checkmark.circle") }
                    else {
                        Label("\(q.affected.count) booking\(q.affected.count == 1 ? "" : "s") will be cancelled. No strikes.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.statusWarning)
                        ForEach(q.affected.prefix(3)) { Text("\($0.title) · \($0.start.cpFormat("EEE MMM d"))").font(.footnote).foregroundStyle(.secondary) }
                        if q.affected.count > 3 { Text("and \(q.affected.count - 3) more").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Label("Personal training packs pause", systemImage: "pause.circle")
                    Label("You cannot check in", systemImage: "qrcode")
                } header: { Text("While frozen") } footer: { Text("Next renewal \(model.nextBillDate.cpDayMonth) · $\(model.nextBillTotal).00") }
                if dts.isAccessibilitySize {
                    Section { Button("Freeze membership") { confirm = true }.primaryAction(full: true) }.listRowBackground(Color.clear)
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Freeze").navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            if !dts.isAccessibilitySize && block == nil {
                Button("Freeze membership") { confirm = true }.primaryAction(full: true).padding(.horizontal).padding(.vertical, 8)
            }
        }
        .confirmationDialog("Freeze from \(q.start.cpDayMonth)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Freeze membership") { model.setFreeze(months: months) }
            Button("Not now", role: .cancel) {}
        } message: { Text("Billing pauses until \(q.restart.cpDayMonth). You can't check in or book while frozen.") }
    }

    private func frozen(_ f: FreezeState) -> some View {
        SuccessPattern(headline: "Freeze set", pill: "Confirmed", primaryTitle: nil, primaryAction: {}, shareText: nil,
                       summary: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Freeze \(f.start.cpDayMonth) – \(f.end.cpDayMonth)").font(.headline)
                Text("\(f.months) month\(f.months == 1 ? "" : "s") · $\(10 * f.months) total. Billing restarts \(f.end.addingDays(1).cpDayMonth).").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }, extra: {
            VStack(spacing: 12) {
                StatusPill(text: "Frozen until \(f.end.cpDayMonth)", symbol: "pause.fill", tone: .neutral)
                if model.isFrozen { Button("Resume early") { model.resumeEarly() }.secondaryAction(full: true); Text("Resuming early bills your plan price for the rest of this cycle.").font(.footnote).foregroundStyle(.secondary) }
                else { Button("Cancel the freeze") { model.freeze = nil }.linkAction(danger: true) }
            }
        })
        .navigationTitle("Freeze").navigationBarTitleDisplayMode(.inline)
    }
}

struct CancelMembershipView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var confirm: Bool? = nil
    var body: some View {
        let date = model.firstBillingDate(onOrAfter: model.thirtyDaysOut)
        List {
            // Same page pattern as Freeze: the question and its line on the page, then what changes in one group.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cancel your membership?").brandFont(.title).accessibilityAddTraits(.isHeader)
                    Text("You keep full access until \(date.cpDayMonth), the first billing date at least 30 days from today. You can reinstate with one tap until then.")
                        .font(.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }
            Section {
                Label("Your pass stops working on \(date.cpDayMonth)", systemImage: "xmark.circle")
                Label("Bookings after that date are cancelled", systemImage: "calendar.badge.minus")
                Label("Personal training packs stay for 12 months", systemImage: "checkmark.circle")
            } header: { Text("What changes") }
            Section {
                Button("Cancel membership", role: .destructive) { confirm = true }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Cancel").navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            Button("Keep my membership") { router.goBack() }.primaryAction(full: true).padding(.horizontal).padding(.vertical, 8)
        }
        .confirmationDialog("Cancel membership on \(date.cpDayMonth)?", item: $confirm, titleVisibility: .visible) { _ in
            Button("Cancel membership", role: .destructive) { model.cancelMembership(); router.goBack(); model.showToast("Cancelling \(date.cpDayMonth). Reinstate any time before.") }
            Button("Keep it", role: .cancel) {}
        }
    }
}
