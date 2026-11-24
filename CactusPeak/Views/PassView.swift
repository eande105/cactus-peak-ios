import SwiftUI

struct PassView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var savedBrightness: CGFloat?
    @State private var walletAlert = false
    @State private var showClubPicker = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let st = model.passState
                List {
                    if hasStrip(st) { stateStrip(st).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) }
                    CheckInPassCard(
                        name: model.member.name, plan: model.member.isTeen ? "Teen pass" : model.member.plan.name,
                        number: model.member.memberNumber, clubName: model.club(model.currentClubID).fullName, code: model.passCode(),
                        codeHidden: hidden(st), checkedInText: checkedText(st),
                        onChangeClub: { showClubPicker = true })
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    if !model.member.isTeen { wallet.listRowBackground(Color.clear) }
                    kidsToday
                    Section {
                        HStack {
                            BusynessMeter(reading: model.busyness(model.club(model.currentClubID)), variant: .inline, now: model.now)
                            Spacer()
                            Text(model.club(model.currentClubID).fullName).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    more
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Pass").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { router.dismissSheet() }.barItem() } }
            .sheet(isPresented: $showClubPicker) { ClubSwitcherSheet(mode: .pass).presentationDetents([.medium, .large]) }
            .alert("Wallet pass not available in this build", isPresented: $walletAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text("A Wallet pass needs a signing certificate and a pass type ID. The button, layout and pass design are final.") }
        }
        .onAppear { boost(true) }
        .onDisappear { boost(false) }
        .onChange(of: scenePhase) { _, p in if p != .active { boost(false) } else { boost(true) } }
        .sensoryFeedback(.success, trigger: model.checkedInAt)
        .onChange(of: model.checkedInAt) { _, v in
            if let v { AccessibilityNotification.Announcement("Checked in at \(v.cpTimeShort)").post(); boost(false) }
        }
    }

    private func hidden(_ st: AppModel.PassState) -> Bool {
        switch st { case .frozen, .seeDesk, .closed, .wrongClub: true; default: false }
    }
    private func checkedText(_ st: AppModel.PassState) -> String? {
        if case .checkedIn(let d) = st { return "Checked in · \(d.cpTimeShort)" }
        return nil
    }

    private func hasStrip(_ st: AppModel.PassState) -> Bool {
        switch st {
        case .frozen, .paymentWarning, .paymentPaused, .seeDesk, .wrongClub, .closed, .beforeDesk: true
        default: model.offline
        }
    }

    // MARK: State strip
    @ViewBuilder private func stateStrip(_ st: AppModel.PassState) -> some View {
        switch st {
        case .frozen(let end):
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(text: "Frozen until \(end.cpDayMonth)", symbol: "pause.fill", tone: .neutral)
                Button("View freeze") { router.dismissSheet(); router.selection = .you; router.paths[.you] = [.membership, .freeze] }.linkAction()
            }
        case .paymentWarning: Banner(tone: .warning, text: "Payment failed. Update your card.", actionTitle: "Update payment") { router.dismissSheet(); router.selection = .you; router.paths[.you] = [.membership] }
        case .paymentPaused: Banner(tone: .danger, text: "New bookings are paused until you pay. Your pass still works.", actionTitle: nil, action: nil)
        case .seeDesk:
            VStack(alignment: .leading, spacing: 8) {
                Text("See the front desk.").brandFont(.title2).foregroundStyle(Color.statusDanger)
                Button("Call the front desk · \(model.club(model.currentClubID).phone)") { openURL(URL(string: "tel:\(model.club(model.currentClubID).phone.filter(\.isNumber))")!) }.primaryAction()
            }
        case .wrongClub(let home): Banner(tone: .warning, text: "Your Trailhead plan covers \(home). A day pass here is $20.", actionTitle: "See plans") { router.dismissSheet(); router.selection = .you; router.paths[.you] = [.membership, .plans] }
        case .closed(let opens): Banner(tone: .info, text: "\(model.club(model.currentClubID).fullName) opens at \(opens)", actionTitle: nil, action: nil)
        case .beforeDesk: Banner(tone: .info, text: "Desk opens at 6 am. Scan at the door reader.", actionTitle: nil, action: nil)
        default:
            if model.offline { StatusPill(text: "Offline code", symbol: "wifi.slash", tone: .neutral) }
        }
    }

    // MARK: Wallet
    @ViewBuilder private var wallet: some View {
        if model.walletAdded { Label("In Apple Wallet", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.statusSuccess).frame(minHeight: 44) }
        else {
            WalletButton { walletAlert = true }.frame(height: 48).frame(maxWidth: .infinity)
                .accessibilityLabel("Add to Apple Wallet").accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder private var kidsToday: some View {
        let kids = model.upcomingBookings.filter { $0.kind == .kids && AZ.cal.isDate($0.start, inSameDayAs: model.now) }
        if let k = kids.first {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kids club today: \(k.detail) · \(k.start.cpTimeShort)–\(k.end.cpTimeShort)").font(.subheadline.weight(.semibold))
                    Text("Show this pass at the kids club desk.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var more: some View {
        Section {
            if model.guestPassesLeft > 0 || !model.member.isTeen {
                Button { router.dismissSheet(); router.selection = .you; router.paths[.you] = [.guestPasses] } label: {
                    Label("Guest pass", systemImage: "person.badge.plus").frame(minHeight: 44)
                }
            }
            Button { router.dismissSheet(); router.selection = .you; router.paths[.you] = [.settings] } label: {
                Label("Pass settings", systemImage: "gearshape").frame(minHeight: 44)
            }
            #if DEBUG
            Button { model.checkIn() } label: {
                Label("Demo: simulate a desk scan", systemImage: "dot.radiowaves.left.and.right").frame(minHeight: 44).foregroundStyle(.secondary)
            }
            #endif
        }
        .tint(.primary)
    }

    // MARK: Brightness and idle timer
    private func boost(_ on: Bool) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let screen = scene?.screen else { return }
        if on, model.prefs.brightnessBoost, !model.checkedInToday {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 1.0
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            if let s = savedBrightness { screen.brightness = s; savedBrightness = nil }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
