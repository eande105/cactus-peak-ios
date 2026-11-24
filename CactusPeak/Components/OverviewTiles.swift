import SwiftUI

// Parts for the overview and browse pages (Today, Book, Clubs): summary tiles in pairs, explore tiles made from brand
// objects, and portrait chips. All are flat cards with the list cards' corner, so they sit with the list around them.

// MARK: - Summary tiles

/// A grid of summary tiles in one clear list row, edge to edge with the cards above and below. Each `SummaryTilePair`
/// is a row of the grid. One list row holds the whole grid, so the rows keep the same gap as the columns and no
/// header or separator comes between them.
struct SummaryTileGrid<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 12) { content }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}

/// Two tiles side by side at the same height. They stack at accessibility sizes.
struct SummaryTilePair<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        // The pair takes its tallest tile's height, and each tile fills it.
        layout { content }.fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Stat cards

/// A Health-style stat card, the one style for every summary tile. From the top: a tinted symbol and name, with when
/// the value is from and a chevron on the trailing side; then the value in Archivo with a small unit; then an optional
/// visual (a meter, a row of days); then one short line. The value sits at the bottom, so values line up across a
/// pair. A tap opens the page behind the number.
struct StatCard<Visual: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    /// When the value is from, such as "Now", "11 am" or "This week".
    var time: String?
    var value: String
    var unit: String?
    var detail: String?
    /// The page behind the number. Without one the card is a plain fact: no chevron and no button.
    var action: (() -> Void)?
    /// More than 1 for a value that is a name ("Climb Cycle"): it wraps in the title role instead of shrinking.
    var valueLines = 1
    /// Puts the value right under the name, so values line up across a pair when only one card has a visual.
    var valueAtTop = false
    var visual: Visual

    init(title: String, symbol: String, tint: Color, time: String?, value: String, unit: String?, detail: String? = nil,
         valueLines: Int = 1, valueAtTop: Bool = false, action: (() -> Void)?, @ViewBuilder visual: () -> Visual) {
        self.title = title; self.symbol = symbol; self.tint = tint; self.time = time
        self.value = value; self.unit = unit; self.detail = detail; self.valueLines = valueLines; self.valueAtTop = valueAtTop
        self.action = action; self.visual = visual()
    }

    var body: some View {
        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            card.accessibilityElement(children: .combine)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if valueAtTop { Color.clear.frame(height: 6) } else { Spacer(minLength: 12) }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).brandFont(valueLines > 1 ? .title2 : .numeral(.large))
                if let unit { Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(Color.secondary) }
            }
            .lineLimit(valueLines > 1 && dts.isAccessibilitySize ? nil : valueLines)
            .minimumScaleFactor(valueLines > 1 ? 1 : 0.7)
            visual
            if let detail { Text(detail).font(.footnote).foregroundStyle(Color.secondary) }
            if valueAtTop { Spacer(minLength: 0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
    }

    @Environment(\.dynamicTypeSize) private var dts

    /// At accessibility sizes the time moves under the name, so neither truncates.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // An HStack, not a Label: in a list a Label pads its icon to the row icon width.
                HStack(spacing: 5) {
                    Image(systemName: symbol).accessibilityHidden(true)
                    Text(title).lineLimit(dts.isAccessibilitySize ? nil : 1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                // The name keeps its room; the time gives way first.
                .layoutPriority(1)
                Spacer(minLength: 4)
                if let time, !dts.isAccessibilitySize { Text(time).font(.footnote).foregroundStyle(Color.secondary).lineLimit(1) }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            if let time, dts.isAccessibilitySize { Text(time).font(.footnote).foregroundStyle(Color.secondary) }
        }
    }
}

extension StatCard where Visual == EmptyView {
    init(title: String, symbol: String, tint: Color, time: String?, value: String, unit: String?, detail: String? = nil,
         valueLines: Int = 1, valueAtTop: Bool = false, action: (() -> Void)?) {
        self.init(title: title, symbol: symbol, tint: tint, time: time, value: value, unit: unit, detail: detail,
                  valueLines: valueLines, valueAtTop: valueAtTop, action: action) { EmptyView() }
    }
}

// MARK: - Explore tiles

/// A browse tile: a name and a count on a flat tint, with a brand object in the corner. Selected tiles get a
/// border and a check, so a tile works as a filter.
struct ExploreTile<Art: View>: View {
    var title: String
    var detail: String?
    var tint: Color
    var textTint: Color
    var selected = false
    var action: () -> Void
    @ViewBuilder var art: Art
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    art.frame(width: 44, height: 44)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").symbolFont(.title3).foregroundStyle(textTint).accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 10)
                Text(title).font(.headline).foregroundStyle(textTint).lineLimit(dts.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                if let detail { Text(detail).font(.footnote).foregroundStyle(Color.secondary).lineLimit(dts.isAccessibilitySize ? nil : 1) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(tint.opacity(scheme == .dark ? 0.22 : 0.13), in: .rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DetailMetrics.cornerRadius, style: .continuous).strokeBorder(tint, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: DetailMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Portrait chips

/// A person as a large portrait with their first name under it. Selected chips get a ring, so a chip works as a
/// filter.
struct PortraitChip: View {
    var name: String
    var label: String
    var category: ClassCategory
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CoachImage(name: name, category: category, size: 64)
                    .padding(3)
                    .overlay { if selected { Circle().strokeBorder(Color.brandAccent, lineWidth: 2.5) } }
                Text(label).font(.footnote.weight(selected ? .semibold : .regular)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Booking tile

/// The art for a booking, like a book cover or a game icon: the category tile for a class, the coach's portrait for
/// personal training, and the space's object on a flat tint for a court, a lane or kids club.
/// The brand Tile (VISUAL-IDENTITY.md): a square field with its top-left corner cut at 60°, never a rounded
/// square. The points match the plate in the cut class art (`category-*-cut`), so a tint field clipped to this shape
/// lines up with that art.
struct CutTileShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.25))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.1443, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

extension View {
    /// A square brand Tile at `size`, cut at the top-left corner. Class art, spaces and coaches all use it, so every
    /// tile in the app has the same outline.
    func tileShape(_ size: CGFloat) -> some View {
        frame(width: size, height: size)
            .clipShape(CutTileShape())
    }
}

struct BookingTile: View {
    @Environment(\.colorScheme) private var scheme
    var booking: Booking
    var coach: Coach?
    var size: CGFloat

    var body: some View {
        Group {
            switch booking.kind {
            case .classSession:
                ClassGraphic(category: booking.category, variant: .square)
            case .pt:
                // The tile has a fixed size, so the portrait inside it must not grow with Dynamic Type.
                if let coach { CoachImage(name: coach.fullName, category: coach.category, size: size, circle: false).dynamicTypeSize(.large) }
                else { space(.strengthFloor) }
            case .court: space(.courts)
            case .lane: space(.lapPool)
            case .kids: space(.kidsClub)
            }
        }
        .tileShape(size)
        .accessibilityHidden(true)
    }

    private func space(_ id: SpaceGraphicID) -> some View {
        SpaceGraphic(id: id)
            .padding(size * 0.18)
            .frame(width: size, height: size)
            .background(booking.category.color.opacity(scheme == .dark ? 0.24 : 0.14))
    }
}
