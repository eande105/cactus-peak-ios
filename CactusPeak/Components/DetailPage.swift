import SwiftUI

// The parts that the class, coach and club pages share: a centred intro, a row of equal action buttons, section
// headers with an optional count and link, glyph rows for facts, and a strip of cards that scrolls sideways.

// MARK: - Intro

/// The top of a detail page: the intro, the main button and the action buttons. It is page chrome, not list data,
/// so it lives in the first section's header. A row clips its content to the card bounds, which cut the edges of
/// the glass button; a header does not clip, and it needs no clear background or hidden separators.
/// The zero insets make the header as wide as the cards below it, so the buttons line up with their edges.
struct DetailHeaderSection<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Section {} header: {
            VStack(spacing: 12) { content }
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets())
                .textCase(nil)
                .font(.body)
        }
    }
}

/// The top of a detail page: the art, the name, then one or two lines and a row of facts, centred on the page
/// background. At accessibility sizes it aligns to the leading edge so long lines wrap from one edge.
/// `titleHidden` turns true when the name scrolls under the bar, so the page can show the name there.
struct DetailIntro<Art: View, Lines: View, Facts: View>: View {
    var title: String
    @Binding var titleHidden: Bool
    @ViewBuilder var art: Art
    @ViewBuilder var lines: Lines
    @ViewBuilder var facts: Facts
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let ax = dts.isAccessibilitySize
        VStack(alignment: ax ? .leading : .center, spacing: 6) {
            art.padding(.bottom, 8)
            Text(title)
                .brandFont(.title)
                .multilineTextAlignment(ax ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .onScrollVisibilityChange(threshold: 0.2) { visible in titleHidden = !visible }
            lines
            facts.padding(.top, 6)
        }
        .multilineTextAlignment(ax ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: ax ? .leading : .center)
        .padding(.top, 4)
        // An explicit colour for the intro text only: inside a header, the hierarchical `.primary` resolves to
        // secondary. Buttons keep the colours their styles give them.
        .foregroundStyle(Color.primary)
    }
}

extension DetailIntro where Facts == EmptyView {
    init(title: String, titleHidden: Binding<Bool>, @ViewBuilder art: () -> Art, @ViewBuilder lines: () -> Lines) {
        self.init(title: title, titleHidden: titleHidden, art: art, lines: lines, facts: { EmptyView() })
    }
}

/// Facts in one centred row, split by dots. When they do not fit, they stack.
struct DetailFacts: View {
    var items: [String]
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let joined = Text(items.joined(separator: " · "))
        Group {
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { ForEach(items, id: \.self) { Text($0) } }
            } else {
                ViewThatFits(in: .horizontal) {
                    joined.lineLimit(1)
                    VStack(spacing: 2) { ForEach(items, id: \.self) { Text($0) } }
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// The name in the bar once the intro's name scrolls away. Text only: the art stays in the intro.
struct DetailBarTitle: View {
    var title: String
    var shown: Bool
    var body: some View {
        Text(title).font(.headline).lineLimit(1)
            .opacity(shown ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: shown)
            .accessibilityHidden(!shown)
    }
}

/// The coach as one line of the intro: a small portrait, "with" and the name, and a chevron to their page.
struct DetailCoachLine: View {
    @Environment(AppRouter.self) private var router
    var coach: Coach
    var category: ClassCategory

    var body: some View {
        Button { router.push(.coach(coach.id)) } label: {
            HStack(spacing: 8) {
                CoachImage(name: coach.fullName, category: category, size: 24)
                Text("\(Text("with ").foregroundStyle(.secondary))\(Text(coach.fullName).fontWeight(.semibold).foregroundStyle(Color.linkText))")
                    .font(.subheadline)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.linkText)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach, \(coach.fullName)")
        .accessibilityHint("Opens the coach's page")
        .accessibilityAddTraits(.isButton)
    }
}

/// A small tag beside the category badge: the same shape, size and type, on a neutral fill, or tinted.
struct DetailTag: View {
    var text: String
    var symbol: String?
    var tint: Color?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint ?? Color.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.map { $0.opacity(scheme == .dark ? 0.14 : 0.10) } ?? Color(.tertiarySystemFill))
        )
    }
}

// MARK: - Stat strip

/// Short facts side by side, like the strip under an app's name in the App Store (ages, rating, size): a label
/// over a visual or a number, with a word under it, split by thin lines. At accessibility sizes the facts stack.
struct DetailStatStrip<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        if dts.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { i, view in
                        if i > 0 { Divider().frame(height: 52) }
                        view.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// One fact in a `DetailStatStrip`: an eyebrow label, then a number or a meter, then a short word.
struct DetailStat<Value: View>: View {
    var label: String
    var detail: String
    /// What VoiceOver reads, when the label and the word alone are not clear ("Crowd, usually steady").
    var accessibilityText: String? = nil
    @ViewBuilder var value: Value
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let ax = dts.isAccessibilitySize
        VStack(alignment: ax ? .leading : .center, spacing: 4) {
            // The system caption, not the brand eyebrow: the eyebrow's wide tracking does not fit a quarter of the
            // width, and the App Store strip uses plain small caps here too.
            Text(label).font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary).lineLimit(1)
            value.frame(height: ax ? nil : 26)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(ax ? nil : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? "\(label), \(detail)")
    }
}

/// The number in a `DetailStat`, in the brand numeral role.
struct DetailStatNumber: View {
    var text: String
    var body: some View { Text(text).brandFont(.numeral(.small)).foregroundStyle(Color.primary) }
}

extension DetailStat where Value == DetailStatNumber {
    /// A fact whose value is a number: "45" over "min".
    init(label: String, number: String, detail: String) {
        self.init(label: label, detail: detail) { DetailStatNumber(text: number) }
    }
}

// MARK: - Date badge

/// A day as a small calendar leaf, like the date in a Calendar or Wallet event row: the weekday over the day number.
struct DateBadge: View {
    var date: Date
    var body: some View {
        VStack(spacing: 0) {
            Text(date.cpFormat("EEE")).brandFont(.eyebrow).foregroundStyle(Color.linkText)
            Text(date.cpFormat("d")).brandFont(.numeral(.small)).foregroundStyle(Color.primary)
        }
        .frame(minWidth: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Cancellation

/// The cancel and waitlist rules for one booking, as glyph rows: when a cancel stops being free, how long the
/// waitlist moves, and the member's late cancels, which open the strike rules. The class and booking pages share it.
struct CancelPolicySection: View {
    @Environment(AppModel.self) private var model
    /// The last moment a cancel is free.
    var cutoff: Date
    /// When the waitlist stops moving people up. Nil when the booking has no waitlist.
    var waitlistUntil: Date? = nil
    /// True when a late cancel counts as a strike (classes, courts, lanes).
    var countsAsStrike: Bool
    /// A line for a booking with its own rule, such as "Kids club has no strikes."
    var note: String? = nil

    var body: some View {
        let day = AZ.cal.isDate(cutoff, inSameDayAs: model.now) ? "today" : cutoff.cpFormat("EEEE")
        Section {
            DetailFactRow(symbol: "arrow.uturn.backward",
                          text: cutoff > model.now ? "Cancel free until \(cutoff.cpTimeShort) \(day)" : "Free cancel ended at \(cutoff.cpTimeShort) \(day)",
                          secondary: countsAsStrike ? "Later counts as a late cancel" : nil)
            if let w = waitlistUntil {
                DetailFactRow(symbol: "list.number", text: "Waitlist moves until \(w.cpTimeShort)",
                              secondary: "You get 30 minutes to confirm a spot")
            }
            if let note { DetailFactRow(symbol: "checkmark.shield", text: note) }
            if countsAsStrike && model.strikesIn30 > 0 {
                NavigationLink(value: AppRoute.strikes) {
                    DetailFactRow(symbol: "exclamationmark.triangle", text: "\(model.strikesIn30) of 3 late cancels",
                                  secondary: "3 in 30 days pause new bookings", tint: .statusWarning)
                }
            }
        } header: {
            DetailSectionHeader(title: waitlistUntil == nil ? "Cancellation" : "Cancellation and waitlist")
        }
    }
}

// MARK: - Hero

/// The top of a page whose content is a place or a piece of media: full-width art that runs under the bar (a map for
/// a club, the class art for a class), then the page's own header under it, aligned to the leading edge as in Maps and
/// Fitness+. Put `.heroPage()` on the list so its content starts under the bar.
struct HeroHeaderSection<Hero: View, Content: View>: View {
    /// The art's height, from the top of the screen.
    var height: CGFloat
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content
    /// The header content's distance from the screen edge, and the screen width, read from the header's position.
    @State private var inset: CGFloat = 20
    @State private var width: CGFloat = 402

    var body: some View {
        Section {} header: {
            VStack(alignment: .leading, spacing: 14) {
                // The art is as wide as the screen: the header sits `inset` in from each edge.
                // It also runs 80 pt above the header, past the list's top padding, to the top of the screen.
                hero
                    .frame(width: width, height: height + 80)
                    .clipped()
                    .padding(.top, -80)
                    .padding(.horizontal, -inset)
                content
            }
            .textCase(nil)
            .font(.body)
            .padding(.bottom, 6)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                if f.minX > 0 { inset = f.minX; width = f.width + 2 * f.minX }
            }
            // The zero insets put the intro on the list cards' edges, as `DetailHeaderSection` does, so the intro
            // and the sections below share one margin: the list's own, from the system. It is the outermost
            // modifier, so the list reads it.
            .listRowInsets(EdgeInsets())
        }
    }
}

extension View {
    /// Lets a list with a `HeroHeaderSection` start under the bar, so the art fills the top of the screen. While the
    /// hero shows (`heroVisible`), the bar has no edge effect, so the art is not blurred under the bar's buttons.
    func heroPage(heroVisible: Bool) -> some View {
        ignoresSafeArea(.container, edges: .top)
            .scrollEdgeEffectHidden(heroVisible, for: .top)
    }
}

// MARK: - Action row

/// Two or three actions of equal width under the intro. At accessibility sizes they stack.
struct DetailActionRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout { content }
            .buttonStyle(DetailActionStyle())
    }
}

/// The label of one action: the glyph above the word, or beside it at accessibility sizes.
struct DetailActionLabel: View {
    var title: String
    var symbol: String
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 4))
        layout {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(height: 22).accessibilityHidden(true)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(dts.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: dts.isAccessibilitySize ? .leading : .center)
    }
}

/// An action button on the card fill, with the list cards' corner.
struct DetailActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Color.linkText : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
    }
}

enum DetailMetrics {
    /// The corner radius of the inset grouped list's cards (measured on iOS 27). New cards use it to match.
    static let cornerRadius: CGFloat = 26
}

// MARK: - Section header

/// A large section title. `detail` is a count or a short state ("3 more", "5 classes"). With `action`, the title
/// has a chevron and the whole header opens the full list.
struct DetailSectionHeader: View {
    var title: String
    var detail: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label(chevron: true) }
                .buttonStyle(.plain)
                .accessibilityHint("Shows all")
        } else {
            label(chevron: false)
        }
    }

    private func label(chevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title).brandFont(.section)
                if chevron { Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(Color.linkText).accessibilityHidden(true) }
            }
            // An explicit colour: inside a header, the hierarchical `.primary` resolves to secondary.
            .foregroundStyle(Color.primary)
            if let detail { Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(Color.linkText) }
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Fact rows

/// One fact: a glyph in an outlined square, then the value. `trailing` holds a meter or a short note.
struct DetailFactRow<Trailing: View>: View {
    var symbol: String
    var text: String
    var secondary: String?
    /// The glyph's colour. A warning fact (a late cancel) takes the warning colour.
    var tint: Color = .linkText
    @ViewBuilder var trailing: Trailing
    /// The glyph's box grows with the text, so the glyph stays inside it at accessibility sizes.
    @ScaledMetric(relativeTo: .callout) private var box: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let ax = dts.isAccessibilitySize
        // At accessibility sizes the glyph, the text and the trailing item stack, so the text has the full width.
        (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 14))) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(tint)
                // Capped, so the glyph does not take over the row at the largest sizes.
                .frame(width: min(box, 56), height: min(box, 56))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                if let secondary { Text(secondary).font(.footnote).foregroundStyle(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !ax { Spacer(minLength: 8) }
            trailing
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension DetailFactRow where Trailing == EmptyView {
    init(symbol: String, text: String, secondary: String? = nil, tint: Color = .linkText) {
        self.init(symbol: symbol, text: text, secondary: secondary, tint: tint, trailing: { EmptyView() })
    }
}

/// A short capsule at the end of a row: "4 left", "Full", "Book".
struct RowPill: View {
    var text: String
    var body: some View {
        Text(text)
            .countFont(.subheadline)
            .foregroundStyle(Color.linkText)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

// MARK: - Card strip

/// A section whose header holds a strip of cards that scroll sideways from screen edge to screen edge. The strip is
/// in the header because a list row clips its content to the card bounds, and a header does not.
struct CardStripSection<Header: View, Item: Identifiable, Card: View>: View {
    var items: [Item]
    /// Cards per visible width: `span` of `count` columns, so the next card shows at the edge.
    var count = 3
    var span = 2
    /// The same at accessibility sizes. By default a card takes most of the width, so its text can wrap.
    var axCount = 4
    var axSpan = 3
    @ViewBuilder var header: Header
    @ViewBuilder var card: (Item) -> Card
    /// The header content's distance from the screen edge, read from its position.
    @State private var headerInset: CGFloat = 36
    /// A section header's text sits this far in from the list card edge.
    private static var headerTextInset: CGFloat { 20 }
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        Section {} header: {
            VStack(alignment: .leading, spacing: 10) {
                header
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            card(item)
                                .containerRelativeFrame(.horizontal, count: dts.isAccessibilitySize ? axCount : count,
                                                        span: dts.isAccessibilitySize ? axSpan : span, spacing: 12)
                        }
                    }
                    .scrollTargetLayout()
                }
                // The first card lines up with the list card edge, in line with the cards above and below.
                .contentMargins(.horizontal, max(headerInset - Self.headerTextInset, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .padding(.horizontal, -headerInset)
                .textCase(nil)
                .font(.body)
                .foregroundStyle(Color.primary)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { x in if x > 0 { headerInset = x } }
        }
    }
}

// MARK: - Primary action

/// The page's main action in the intro: full width, glass prominent, with the colours SwiftUI gives that style.
struct DetailPrimaryButton: View {
    var title: String
    /// A short second line inside the button, such as the plan that covers the booking.
    var subtitle: String? = nil
    var role: ButtonRole? = nil
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
        }
        .accentProminent()
        .controlSize(.large)
        // A capsule around wrapped text turns into a circle, so accessibility sizes get a rounded rectangle.
        .buttonBorderShape(dts.isAccessibilitySize ? .roundedRectangle(radius: DetailMetrics.cornerRadius) : .capsule)
    }
}

/// The intro control for a booked item: Cancel booking as the main button, with the time left to cancel free as
/// its second line, and a glass circle QR button that opens the pass with a zoom out of itself.
struct BookedActionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.zoomNamespace) private var zoomNamespace
    /// The last moment a cancel is free.
    var cancelCutoff: Date
    /// The zoom source id. Each page uses its own, so the pass zooms back to the right button.
    var passSourceID: String
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // model.now drives the countdown, so the line follows the app clock.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                DetailPrimaryButton(title: "Cancel booking", subtitle: CancelText.left(until: cancelCutoff, now: model.now),
                                    role: .destructive, action: onCancel)
            }
            Button { router.present(.pass, zoomFrom: passSourceID) } label: {
                Image(systemName: model.checkedInToday ? "checkmark" : "qrcode")
                    .symbolFont(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.primary)
            .zoomSource(passSourceID, in: zoomNamespace)
            .accessibilityLabel("Show pass")
            .accessibilityValue(model.checkedInToday ? "Checked in" : "")
        }
    }
}

enum CancelText {
    /// "2 hr, 10 min left to cancel free", or the strike warning once the cutoff has passed.
    static func left(until cutoff: Date, now: Date) -> String {
        let secs = cutoff.timeIntervalSince(now)
        guard secs > 0 else { return "Late cancel counts as a strike" }
        let left = Duration.seconds(max(60, secs))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
        return "\(left) left to cancel free"
    }
}

/// The pass in the bar once the intro's QR button scrolls away. Put `.zoomSource(sourceID, in:)` on the item.
struct DetailBarPassButton: View {
    @Environment(AppRouter.self) private var router
    var sourceID: String
    var body: some View {
        Button { router.present(.pass, zoomFrom: sourceID) } label: { Image(systemName: "qrcode") }
            .barItem()
            .accessibilityLabel("Show pass")
    }
}

/// The same action in the bar once the intro's button scrolls away: a compact glass prominent button.
struct DetailBarButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action)
            .accentProminent()
            .fontWeight(.semibold)
    }
}

extension View {
    /// The brand's main button: prominent glass in the accent, with `brandOnAccent` text. In dark mode the accent is a
    /// light copper, where the default white label has too little contrast, so the label turns dark there.
    func accentProminent() -> some View {
        buttonStyle(.glassProminent).tint(Color.brandAccent).foregroundStyle(Color.brandOnAccent)
    }

    /// Reports when the view scrolls under the bar, so the page can show its action there.
    func reportsHidden(_ hidden: Binding<Bool>) -> some View {
        onScrollVisibilityChange(threshold: 0.3) { visible in hidden.wrappedValue = !visible }
    }
}
