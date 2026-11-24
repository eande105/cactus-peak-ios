import SwiftUI

/// The day picker, like the week strip in an Apple Fitness plan: a weekday letter over each date, a filled circle on
/// the selected day, today's date in the accent, and a dot under each day with one of the member's bookings. The days
/// share the width when they fit; a longer window scrolls.
struct ScheduleDayStrip: View {
    var days: [Date]
    @Binding var selected: Date
    var counts: (Date) -> Int?
    var dimmed: (Date) -> Bool
    /// True for a day with one of the member's bookings.
    var booked: (Date) -> Bool = { _ in false }
    var onCalendar: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dts

    /// Days that share the width without scrolling.
    private static let fitCount = 8

    var body: some View {
        HStack(spacing: 0) {
            if days.count <= Self.fitCount {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in chip(d).frame(maxWidth: .infinity) }
                    // A short window (courts: 4 days) keeps a week's spacing, as the Fitness week strip does.
                    ForEach(days.count..<max(days.count, 7), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
                .padding(.leading, BookHeader.margin - 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { d in chip(d).frame(width: 44).id(d) }
                        }
                    }
                    .contentMargins(.horizontal, BookHeader.margin - 4, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
                    .onChange(of: selected) { _, new in withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            if let onCalendar {
                Button(action: onCalendar) { Image(systemName: "calendar").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(Color.primary).accessibilityLabel("Pick a date")
                    .padding(.trailing, BookHeader.margin - 8)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func chip(_ d: Date) -> some View {
        let isSel = AZ.cal.isDate(d, inSameDayAs: selected)
        let dim = dimmed(d)
        let isToday = d == AppModel.shared.now.startOfAZDay
        let n = counts(d)
        let numberColor: Color = isSel ? Color.brandOnAccent : (isToday ? Color.linkText : Color.primary)
        return Button { withAnimation(.snappy(duration: 0.25)) { selected = d } } label: {
            VStack(spacing: 4) {
                Text(d.cpFormat("EEEEE")).font(.caption2.weight(.semibold)).foregroundStyle(Color.secondary)
                Text(d.cpFormat("d")).brandFont(.numeral(.small)).foregroundStyle(numberColor)
                    .frame(width: 36, height: 36)
                    .background { if isSel { Circle().fill(Color.brandAccent) } }
                // A count while filters are on; otherwise a dot for a day with a booking.
                Group {
                    if let n { Text("\(n)").countFont(.caption2, weight: .medium).foregroundStyle(Color.secondary) }
                    else { Circle().fill(booked(d) ? Color.brandAccent : Color.clear).frame(width: 5, height: 5) }
                }
                .frame(height: 10)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(dim && !isSel ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isToday ? "Today, " : "")\(d.cpFormat("EEEE MMMM d"))\(booked(d) ? ", booked" : "")\(n.map { ", \($0) \($0 == 1 ? "option" : "options")" } ?? "")")
        .accessibilityAddTraits(isSel ? [.isSelected, .isButton] : .isButton)
    }
}

struct DurationChips: View {
    var options: [Int]
    @Binding var selected: Int
    var disabled: Set<Int> = []
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        Group {
            if dts.isAccessibilitySize {
                Picker("Duration", selection: $selected) { ForEach(options, id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.menu)
            } else {
                Picker("Duration", selection: $selected) { ForEach(options, id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.segmented)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// One bookable time for courts, lap lanes or kids club, built like the rows on Today ("Coming up"): a leading time
/// block, a glance at what is free in the middle, and the same `RowPill` on the trailing edge. The time block reads
/// like a Calendar day list (start bold, end under it). Each booking type passes its own glance (`CourtTiles`,
/// `LaneStrips`, or a `RibMeter` for kids club spots) and a short status line under it.
struct ReserveSlotRow<Glance: View>: View {
    var start: Date
    var end: Date
    /// The line under the glance: "2 of 4 open", "Full", "Started".
    var status: String
    /// The trailing pill ("Book", "Join waitlist"), or nil when the time cannot be booked.
    var pill: String?
    var past = false
    /// What VoiceOver reads after the times. Defaults to the status line.
    var a11yDetail: String?
    @ViewBuilder var glance: () -> Glance
    @Environment(\.dynamicTypeSize) private var dts
    /// Fits "12:45 pm" in the headline style, so every row's glance starts on the same line.
    @ScaledMetric(relativeTo: .headline) private var timeWidth: CGFloat = 84

    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 1) {
                Text(start.cpTimeShort).font(.headline)
                Text(end.cpTimeShort).font(.subheadline).foregroundStyle(Color.secondary)
            }
            .monospacedDigit()
            .frame(width: dts.isAccessibilitySize ? nil : timeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                glance()
                Text(status).font(.subheadline).foregroundStyle(Color.secondary)
            }
            if !dts.isAccessibilitySize { Spacer(minLength: 8) }
            if let pill { RowPill(text: pill) }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .opacity(past ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(start.cpTimeShort) to \(end.cpTimeShort). \(a11yDetail ?? status)")
        .accessibilityAddTraits(pill != nil ? .isButton : [])
    }
}

/// Open = solid brand green, taken = grey. The same two states for a court tile and a lane strip.
private struct SlotFill {
    static func color(open: Bool) -> AnyShapeStyle {
        open ? AnyShapeStyle(Color.brandSecondary) : AnyShapeStyle(Color(.tertiarySystemFill))
    }
}

/// Each court as a small numbered tile, open or taken, so the free courts read at a glance, the way a seat map does
/// in Apple's ticketing sheets.
struct CourtTiles: View {
    var total: Int
    /// Court numbers that are open, 1 to `total`. Pass none when the time is past or booking is paused.
    var open: [Int]
    @ScaledMetric(relativeTo: .caption) private var tile: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(total, 1), id: \.self) { court in
                let isOpen = open.contains(court)
                Text("\(court)")
                    .countFont(.caption, weight: .semibold)
                    // The page colour on the brand green: white in light mode, near black on the cream of dark mode.
                    .foregroundStyle(isOpen ? Color(.systemBackground) : Color.secondary)
                    .frame(width: tile, height: tile)
                    .background(SlotFill.color(open: isOpen), in: .rect(cornerRadius: tile * 0.28, style: .continuous))
            }
        }
    }
}

/// Each lane as a tall strip, like the pool seen from above: solid when the lane is free, half filled when one
/// swimmer is in it and a second can share, grey when it is full.
struct LaneStrips: View {
    /// Swimmers per lane: 0 free, 1 shared, 2 full.
    var swimmers: [Int]
    /// False when the time is past or booking is paused: every lane shows as taken.
    var bookable = true
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(swimmers.enumerated()), id: \.offset) { _, n in
                let state = bookable ? n : 2
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SlotFill.color(open: state == 0))
                    .overlay(alignment: .bottom) {
                        if state == 1 {
                            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3, style: .continuous)
                                .fill(Color.brandSecondary).frame(height: height / 2)
                        }
                    }
                    .frame(width: 10, height: height)
            }
        }
    }
}

