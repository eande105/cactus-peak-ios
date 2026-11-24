import SwiftUI

/// Welcome, sign in and the five onboarding steps. Presented as a full-screen cover until both are done.
struct WelcomeFlow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.signedIn { WelcomeView() }
        else { OnboardingFlow() }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dts
    @State private var showSignIn = false
    @State private var demoBusy = false
    @State private var message: String?

    // After the Apple Fitness+ offer screen: art fills the top, one centred title and line, then one full-width
    // action with a quiet second choice. The art is the brand's object tiles around the peak, as on web sign-in.
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !dts.isAccessibilitySize { WelcomeArt().frame(height: 380) }
                VStack(spacing: 12) {
                    // The one custom-font headline in the app outside the Pass: the welcome is where the brand belongs.
                    Text("Climb at your own pace.").brandFont(.display)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text("Book classes, courts, lap lanes and kids club at five clubs in Mesa and Gilbert.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle").font(.footnote)
                            .foregroundStyle(Color.statusDanger)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, dts.isAccessibilitySize ? 48 : 28)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(edges: dts.isAccessibilitySize ? [] : .top)
        .background(Color(.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button { showSignIn = true } label: { Text("Sign in").fontWeight(.semibold) }
                    .primaryAction(full: true)
                #if DEBUG
                if BackendConfig.current?.demoPassword != nil {
                    Menu {
                        ForEach(DemoAccount.allCases) { acc in
                            Button(acc.title) { signInDemo(acc) }
                        }
                    } label: {
                        HStack { if demoBusy { ProgressView() }; Text("Use a demo account") }
                            .frame(maxWidth: .infinity)
                    }
                    // A Menu takes no primitive button style, so it gets the bordered style directly.
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                    .tint(Color.brandSecondary).disabled(demoBusy)
                }
                #endif
                Button("Not a member yet? Try a 3-day pass") { openURL(URL(string: "https://cactuspeak.example/try")!) }
                    .linkAction().font(.subheadline)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
        }
        .sheet(isPresented: $showSignIn) { PasswordSignInSheet() }
    }

    private func signInDemo(_ acc: DemoAccount) {
        demoBusy = true
        message = nil
        Task {
            do { try await model.signInDemo(acc) } catch { message = BackendError(error).localizedDescription }
            demoBusy = false
        }
    }
}

/// The welcome art: the class objects in cut tiles on Night, around a large copper tile with the peak. The same
/// composition as the web sign-in panel. Decorative only.
private struct WelcomeArt: View {
    // (category, x, y, size) on a 390 x 380 canvas; the centre tile sits at (195, 200).
    private let tiles: [(ClassCategory, CGFloat, CGFloat, CGFloat)] = [
        (.strength, 70, 120, 76), (.cycle, 318, 108, 84), (.aqua, 40, 268, 60),
        (.mindBody, 112, 330, 64), (.court, 288, 318, 72), (.recovery, 360, 232, 52),
        (.conditioning, 196, 64, 56),
    ]
    var body: some View {
        GeometryReader { geo in
            // Scale the 390 x 380 canvas to fit, and centre it, so a wide window (iPad) keeps the composition.
            let k = min(geo.size.width / 390, geo.size.height / 380)
            let dx = (geo.size.width - 390 * k) / 2
            ZStack {
                Color.nightSurface
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    // The square variant is already the category's cut tile.
                    ClassGraphic(category: t.0, variant: .square)
                        .frame(width: t.3 * k, height: t.3 * k)
                        .position(x: dx + t.1 * k, y: t.2 * k + 20)
                }
                RibPeakShape().fill(Color.nightSurface)
                    .padding(30 * k)
                    .frame(width: 132 * k, height: 132 * k)
                    .background(Color.dawnCopper)
                    .clipShape(CutTileShape())
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    .position(x: dx + 195 * k, y: 220 * k)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// Email and password sign-in against Supabase Auth. Wrong details and network failures read differently.
struct PasswordSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    enum Field { case email, password }

    private var canSubmit: Bool { email.contains("@") && !password.isEmpty && !busy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password).focused($focus, equals: .password).submitLabel(.go).onSubmit { submit() }
                } footer: {
                    Text("Use the email on your membership.")
                }
                if let error {
                    Section { Label(error, systemImage: "xmark.circle.fill").foregroundStyle(Color.statusDanger) }
                }
            }
            .navigationTitle("Sign in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Sign in") { submit() }.disabled(!canSubmit) }
                }
            }
            .onAppear { focus = .email }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        Task {
            do {
                try await model.signIn(email: email, password: password)
                dismiss()
            } catch {
                self.error = BackendError(error).localizedDescription
                password = ""
                focus = .password
            }
            busy = false
        }
    }
}

// MARK: - Onboarding

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @AppStorage("cp.onboardStep") private var step = 1
    @State private var selectedClub: ClubID?
    @State private var alertsAsked = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    RibMeter(value: step, tone: .brand, size: .md, peak: false)
                    Text("Step \(step) of 5").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                Group {
                    switch step {
                    case 1: homeClub
                    case 2: interests
                    case 3: alerts
                    case 4: wallet
                    default: ready
                    }
                }
            }
            .screenBackground()
            .toolbar {
                if step > 1 { ToolbarItem(placement: .topBarLeading) { Button { step -= 1 } label: { Label("Back", systemImage: "chevron.left") }.barItem() } }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { selectedClub = model.member.homeClubID }
    }

    // Steps
    private func stepHeader(_ title: String, _ body: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).brandFont(.display).accessibilityAddTraits(.isHeader)
            if let body { Text(body).font(.body).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var homeClub: some View {
        List {
            Section {
                stepHeader("Pick your home club", "You can change this any time.").listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                Button { selectedClub = model.clubs.min { $0.distanceMiles < $1.distanceMiles }?.id } label: { Label("Use my location", systemImage: "location") }.secondaryAction().listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.clubs.sorted { $0.distanceMiles < $1.distanceMiles }) { c in
                    Button { selectedClub = c.id } label: {
                        ClubCard(club: c, reading: model.busyness(c), now: model.now, variant: .listRow, closest: c.distanceMiles == model.clubs.map(\.distanceMiles).min(), selected: selectedClub == c.id)
                    }.buttonStyle(.plain)
                }
            } footer: { Text("Trailhead covers one home club. You can change it once per billing cycle. Ridge and Summit cover all 5.") }
        }
        .listStyle(.insetGrouped)
    }

    private var interests: some View {
        List {
            Section {
                stepHeader("What do you like?", "Pick as many as you want.").listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            }
            Section {
                ForEach(ClassCategory.allCases) { c in
                    let on = model.prefs.interests.contains(c)
                    Button { if on { model.prefs.interests.remove(c) } else { model.prefs.interests.insert(c) } } label: {
                        HStack(alignment: .top) {
                            // At large text the icon stacks above the name, so a word is never split across lines.
                            ViewThatFits(in: .horizontal) {
                                Label { Text(c.title).foregroundStyle(.primary).fixedSize() } icon: { Image(systemName: c.symbol).foregroundStyle(c.textColor) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: c.symbol).foregroundStyle(c.textColor)
                                    Text(c.title).foregroundStyle(.primary).minimumScaleFactor(0.6)
                                }
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark").foregroundStyle(Color.brandAccent).fontWeight(.bold) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var alerts: some View {
        @Bindable var model = model
        return Form {
            Section { stepHeader("Alerts").listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4)) }
            Section {
                Toggle("Waitlist spots", isOn: $model.prefs.notifWaitlist)
                Toggle("Class reminders \u{B7} \(model.prefs.reminderLead) min before", isOn: $model.prefs.notifReminders)
                Toggle("Club news", isOn: $model.prefs.notifClubNews)
                Toggle("Show next class on Lock Screen", isOn: $model.prefs.liveActivities)
            } footer: { Text("Waitlist spot? You get 30 minutes to confirm.") }
        }
    }

    private var wallet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader("Your pass, ready")
                // The pass preview is a brand object, so it stays on the Night surface.
                VStack(alignment: .leading, spacing: 6) {
                    Image("LogoHorizontalReversed").resizable().scaledToFit().frame(height: 22).accessibilityHidden(true)
                    Text(model.member.name).brandFont(.section).foregroundStyle(Color.nightOnSurface)
                    Text(model.member.memberNumber).codeFont(.title2, weight: .bold).foregroundStyle(Color.nightOnSurface)
                }.frame(maxWidth: .infinity, alignment: .leading).nightCard(padding: 20, radius: 24)
                WalletButton { model.walletAdded = false }.frame(height: 50)
                Text("Open your pass from the Lock Screen. No app needed.").font(.subheadline).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private var ready: some View {
        List {
            Section {
                stepHeader("You're set").listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            }
            Section {
                LabeledContent("Home club", value: model.club(selectedClub ?? model.member.homeClubID).fullName)
                LabeledContent("Interests", value: model.prefs.interests.isEmpty ? "All" : model.prefs.interests.map(\.title).sorted().joined(separator: ", "))
                LabeledContent("Alerts", value: model.prefs.notifWaitlist ? "On" : "Off")
            }
            if let s = suggestion {
                Section("Try this tomorrow") {
                    ClassFeatureCard(data: model.rowData(s)).listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    private var suggestion: ClassSession? {
        let d = model.now.startOfAZDay.addingDays(1)
        return model.sessions(club: selectedClub ?? model.member.homeClubID, day: d).first { model.prefs.interests.contains($0.category) } ?? model.sessions(club: selectedClub ?? model.member.homeClubID, day: d).first
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 4) {
            Button(primaryTitle) { advance() }.primaryAction(full: true).disabled(step == 1 && selectedClub == nil)
            if step > 1 && step < 5 { Button(step == 3 ? "Not now" : (step == 4 ? "Maybe later" : "Skip")) { step += 1 }.linkAction() }
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 8).background(.bar)
    }
    private var primaryTitle: String { switch step { case 1, 2: "Continue"; case 3: "Turn on alerts"; case 4: "Continue"; default: "Go to Today" } }
    private func advance() {
        switch step {
        case 1: if let c = selectedClub { model.setHomeClub(c) }; step = 2
        case 3: Task { model.notificationsAuthorized = await NotificationSupport.shared.requestAuthorization(); step = 4 }
        case 5:
            model.onboarded = true; step = 1; router.selection = .today
            model.publishSnapshot()
        default: step += 1
        }
    }
}
