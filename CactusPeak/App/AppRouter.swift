import SwiftUI
import Observation

enum AppRoute: Hashable, Codable {
    case classSession(SessionID)
    case bookingConfirmed(BookingID)
    case bookingDetail(BookingID)
    case myBookings
    case progress
    case notifications
    case club(ClubID)
    case coach(CoachID)
    case coachList(ClubID?)
    case membership
    case plans
    case freeze
    case cancelMembership
    case billingHistory
    case family
    case familyMember(PersonID)
    case guestPasses
    case settings
    case strikes
    case clubClasses(ClubID)
}

enum SwitcherMode: Hashable {
    case viewing          // Today, Book and Clubs: the current club
    case pass             // the pass sheet's club choice. It sets the same current club.
}

struct CancelRequest: Hashable { var bookingID: BookingID }

enum AppSheet: Identifiable, Hashable {
    case pass
    case cancel(BookingID)
    case waitlist(SessionID)
    case clubSwitcher(SwitcherMode)
    case hours(ClubID)
    case invite(SessionID)
    case feedback(BookingID)
    case reserve(ReserveRequest)
    case filters
    case datePicker
    case guestShare
    case addFamily
    case comparePlans
    case planConfirm(PlanTier)
    case freezeConfirm(Int)
    case ptPicker(CoachID)
    case editProfile
    case calendar(BookingID)
    case goal
    /// A full page (Notifications, Bookings, Settings) opened from a toolbar button. It zooms out of the button
    /// as a sheet with its own navigation stack (`pagePath`) instead of being pushed on the tab's stack.
    case page(AppRoute)

    var id: String {
        switch self {
        case .page(let r): "page-\(r)"
        case .pass: "pass"
        case .cancel(let i): "cancel-\(i)"
        case .waitlist(let i): "waitlist-\(i)"
        case .clubSwitcher(let m): "switcher-\(m)"
        case .hours(let i): "hours-\(i)"
        case .invite(let i): "invite-\(i)"
        case .feedback(let i): "feedback-\(i)"
        case .reserve(let r): "reserve-\(r.id)"
        case .filters: "filters"
        case .datePicker: "date"
        case .guestShare: "guest"
        case .addFamily: "addfamily"
        case .comparePlans: "compare"
        case .planConfirm(let p): "plan-\(p.rawValue)"
        case .freezeConfirm(let m): "freeze-\(m)"
        case .ptPicker(let c): "pt-\(c)"
        case .editProfile: "profile"
        case .calendar(let b): "cal-\(b)"
        case .goal: "goal"
        }
    }
}

enum AppTab: String, Hashable, Codable, CaseIterable { case today, book, clubs, you, search }
enum BookSegment: String, CaseIterable, Identifiable, Hashable { case classes = "Classes", courts = "Courts", lanes = "Lap lanes", kids = "Kids club"; var id: String { rawValue } }

struct ScheduleFilters: Equatable {
    var categories: Set<ClassCategory> = []
    var times: Set<TimeOfDay> = []
    var maxIntensity = 5
    var coachID: CoachID?
    var firstTimers = false
    var spotsOnly = false
    var myBookings = false
    var activeCount: Int {
        (categories.isEmpty ? 0 : 1) + (times.isEmpty ? 0 : 1) + (maxIntensity < 5 ? 1 : 0)
        + (coachID == nil ? 0 : 1) + (firstTimers ? 1 : 0) + (spotsOnly ? 1 : 0) + (myBookings ? 1 : 0)
    }
}

enum TimeOfDay: String, CaseIterable, Identifiable, Hashable {
    case early = "Early morning", morning = "Morning", midday = "Midday", evening = "Evening"
    var id: String { rawValue }
    var detail: String {
        switch self { case .early: "Before 8 am"; case .morning: "8 am to noon"; case .midday: "Noon to 4 pm"; case .evening: "4 pm on" }
    }
    static func of(_ d: Date) -> TimeOfDay {
        let h = AZ.cal.component(.hour, from: d)
        return h < 8 ? .early : h < 12 ? .morning : h < 16 ? .midday : .evening
    }
}

struct ClashPrompt: Identifiable, Hashable {
    var id: SessionID; var existing: String; var existingTime: String
    /// `existingTime` already ends with a period ("5:30 am"), so the next sentence starts after it.
    var message: String { "You are already booked in \(existing) at \(existingTime) Book both?" }
}

@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()

    var selection: AppTab = .today {
        didSet {
            persist()
            // A page sheet belongs to the tab that opened it, so a tab switch closes it.
            if oldValue != selection, case .page = sheet { dismissPage() }
        }
    }
    var paths: [AppTab: [AppRoute]] = [:] { didSet { persist() } }
    var sheet: AppSheet? { didSet { if sheet == nil { zoomSourceID = nil; pagePath = []; subSheet = nil } } }
    /// The toolbar button the current sheet zooms out of (`matchedTransitionSource` id), or nil for the default
    /// slide-up. Set it with `present(_:zoomFrom:)`.
    var zoomSourceID: String?
    /// The navigation stack inside a `.page` sheet. `push` without a tab appends here while a page is open.
    var pagePath: [AppRoute] = []
    /// A sheet opened from inside a `.page` sheet. It stacks on the page instead of replacing it.
    var subSheet: AppSheet?
    var showWelcome = false
    var showOnboarding = false
    var toastMessage: String?

    // Book state
    var segment: BookSegment = .classes
    var day: Date = AZ.date(2026, 10, 27)
    var filters = ScheduleFilters()
    var sport: CourtSport = .pickleball
    var duration = 90
    var confirmHoldFor: SessionID?     // deep link ?action=confirm
    var pendingSheetAfterDismiss: AppSheet?
    var searchText = ""
    var clash: ClashPrompt?
    var rootReady = false
    var lateCancelID: BookingID?

    init() { restore() }

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }
    func push(_ r: AppRoute, on tab: AppTab? = nil) {
        if case .page = sheet {
            if tab == nil { pagePath.append(r); return }
            dismissPage()
        }
        let t = tab ?? selection
        paths[t, default: []].append(r)
    }
    func popToRoot(_ tab: AppTab? = nil) { paths[tab ?? selection] = [] }
    func goBack() { if var p = paths[selection], !p.isEmpty { p.removeLast(); paths[selection] = p } }

    /// Only one sheet shows at a time. A new request closes the current one first.
    func present(_ s: AppSheet) {
        if case .page = sheet, s != sheet {
            if case .page = s {} else { subSheet = s; return }
        }
        if sheet != nil, sheet != s {
            sheet = nil
            Task { try? await Task.sleep(for: .milliseconds(450)); self.sheet = s }
        } else { sheet = s }
    }
    /// Closes the top sheet: a sheet on a page first, then the page or sheet itself.
    func dismissSheet() { if subSheet != nil { subSheet = nil } else { sheet = nil } }
    func dismissPage() { subSheet = nil; sheet = nil }

    /// Opens a sheet that zooms out of the toolbar item marked with `.matchedTransitionSource(id: sourceID, in:)`.
    func present(_ s: AppSheet, zoomFrom sourceID: String) {
        zoomSourceID = sourceID
        present(s)
        zoomSourceID = sourceID
    }

    /// A late cancel counts as a strike, so it asks with a confirmation dialog. A free cancel opens the sheet.
    func requestCancel(_ id: BookingID) {
        lateCancelID = id
    }

    // MARK: Deep links (cactuspeak://… and the same paths on the universal-link domain)
    func open(_ url: URL) {
        var parts = url.pathComponents.filter { $0 != "/" }
        if let h = url.host(percentEncoded: false), url.scheme == "cactuspeak" { parts.insert(h, at: 0) }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let m = AppModel.shared
        sheet = nil
        guard let first = parts.first else { selection = .today; return }
        switch first {
        case "pass": selection = .today; present(.pass)
        case "book":
            selection = .book
            if parts.count >= 3, parts[1] == "class" {
                paths[.book] = [.classSession(parts[2])]
                if q.first(where: { $0.name == "action" })?.value == "confirm" { confirmHoldFor = parts[2] }
            } else if parts.count >= 2 {
                switch parts[1] {
                case "courts": segment = .courts
                case "lanes": segment = .lanes
                case "kids": segment = .kids
                default: segment = .classes
                }
                if let slug = q.first(where: { $0.name == "club" })?.value, let c = m.clubs.first(where: { $0.slug == slug }) {
                    m.currentClubID = c.id
                }
            }
        case "clubs":
            selection = .clubs
            if parts.count >= 2, let c = m.clubs.first(where: { $0.slug == parts[1] }) {
                paths[.clubs] = [.club(c.id)]
                if parts.count >= 3, parts[2] == "hours" { Task { try? await Task.sleep(for: .milliseconds(500)); self.present(.hours(c.id)) } }
            } else { paths[.clubs] = [] }
        case "bookings": selection = .today; paths[.today] = [.myBookings]
        case "coaches": if parts.count >= 2 { selection = .clubs; paths[.clubs] = [.coach(parts[1])] }
        case "progress": selection = .you; paths[.you] = [.progress]
        case "inbox": selection = .you; paths[.you] = [.notifications]
        case "membership":
            selection = .you
            if parts.count >= 2, parts[1] == "freeze" { paths[.you] = [.membership, .freeze] }
            else if parts.count >= 2, parts[1] == "plans" { paths[.you] = [.membership, .plans] }
            else { paths[.you] = [.membership] }
        case "family": selection = .you; paths[.you] = [.family]
        case "guest": selection = .you; paths[.you] = [.guestPasses]
        default:
            selection = .today
            m.showToast("That link does not match anything in the app.")
        }
    }

    // MARK: Restoration (warm launch within 30 minutes)
    private func persist() {
        let d = UserDefaults.standard
        d.set(selection.rawValue, forKey: "cp.tab")
        let enc = paths.compactMapValues { try? JSONEncoder().encode($0) }
        d.set(Dictionary(uniqueKeysWithValues: enc.map { ($0.key.rawValue, $0.value) }), forKey: "cp.paths")
        d.set(Date(), forKey: "cp.savedAt")
    }
    private func restore() {
        let d = UserDefaults.standard
        guard let saved = d.object(forKey: "cp.savedAt") as? Date, Date().timeIntervalSince(saved) < 30 * 60 else { return }
        if let t = d.string(forKey: "cp.tab"), let tab = AppTab(rawValue: t) { selection = tab }
        if let dict = d.dictionary(forKey: "cp.paths") as? [String: Data] {
            for (k, v) in dict {
                if let tab = AppTab(rawValue: k), let p = try? JSONDecoder().decode([AppRoute].self, from: v) { paths[tab] = p }
            }
        }
    }
}

extension ReserveKind {
    init?(from seg: BookSegment) {
        switch seg { case .courts: self = .court; case .lanes: self = .lane; case .kids: self = .kidsClub; case .classes: return nil }
    }
    var title: String { switch self { case .court: "Courts"; case .lane: "Lap lanes"; case .kidsClub: "Kids club" } }
    var segment: BookSegment { switch self { case .court: .courts; case .lane: .lanes; case .kidsClub: .kids } }
}
