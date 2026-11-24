import SwiftUI

/// Everything a class row needs, so rows do not read the whole model.
struct ClassRowData: Identifiable, Hashable {
    var session: ClassSession
    var coach: Coach
    var clubShort: String
    var left: Int
    var waitlist: Int
    var state: BookingState
    /// "Usually busy at 6 pm": the club's typical crowd at the class hour. Typical, not live.
    var crowd: String
    var id: String { session.id }
}

extension AppModel {
    func rowData(_ s: ClassSession) -> ClassRowData {
        ClassRowData(session: s, coach: coach(s.coachID), clubShort: club(s.clubID).shortName, left: spotsLeft(s),
                     waitlist: waitlistCount(s), state: state(for: s),
                     // Name the class time, not the hour start: a 5:30 am class says "at 5:30 am".
                     crowd: CrowdText.usually(level: club(s.clubID).typicalLevel(at: s.start)) + " at " + s.start.cpTimeShort)
    }
}

/// One schedule row, like a Fitness+ workout row. Leading: the class's crop graphic as a thumbnail, with the start
/// time on it as a badge. Middle: the class name, then the coach and the length. Trailing: a small booking button
/// with the spots caption under it. No chevron. The room, the crowd and the intensity live on the class screen.
struct ClassRow: View {
    var data: ClassRowData
    var showClub = false
    var showDate = false
    var onAction: () -> Void
    var onLeave: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .subheadline) private var thumbWidth: CGFloat = 92

    private var isPast: Bool { if case .started = data.state { return true } else { return false } }

    var body: some View {
        let s = data.session
        Group {
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail(s)
                    titleLine(s)
                    detailLine(s)
                    capacity(s)
                    BookingStateButton(state: data.state, action: onAction, onLeave: onLeave)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    thumbnail(s)
                    VStack(alignment: .leading, spacing: 2) {
                        titleLine(s)
                        detailLine(s)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(a11yLabel(s))
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        BookingStateButton(state: data.state, action: onAction, onLeave: onLeave)
                        capacity(s)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .opacity(isPast ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    /// The 16:9 crop, with the start time (and the day, when rows span days) on a material badge.
    private func thumbnail(_ s: ClassSession) -> some View {
        Color.clear
            .frame(width: thumbWidth, height: thumbWidth * 9 / 16)
            .overlay { ClassGraphic(category: s.category, variant: .wide) }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(showDate ? "\(s.start.cpWeekdayShort) \(s.start.cpTimeShort)" : s.start.cpTimeShort)
                    .font(.caption2.weight(.bold)).monospacedDigit().lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .padding(4)
            }
            .accessibilityHidden(true)
    }

    private func titleLine(_ s: ClassSession) -> some View {
        Text(s.name).font(.headline).lineLimit(2)
    }

    /// One short line: the coach, then the club when rows mix clubs, otherwise the length.
    private func detailLine(_ s: ClassSession) -> some View {
        Text("\(data.coach.shortName) · \(showClub ? data.clubShort : "\(s.durationMin) min")")
            .font(.subheadline).foregroundStyle(Color.secondary).lineLimit(1)
    }

    @ViewBuilder private func capacity(_ s: ClassSession) -> some View {
        if case .booked = data.state { EmptyView() }
        else if case .restricted(.notOpen(let d)) = data.state {
            Text("Opens \(d.cpWeekdayShort) \(d.cpTimeShort)").font(.caption).foregroundStyle(Color.secondary)
        } else {
            let dropIn: Bool = { if case .dropIn = data.state { return true } else { return false } }()
            let low = data.left > 0 && data.left <= 5
            HStack(spacing: 3) {
                if low { Image(systemName: "exclamationmark.triangle.fill").imageScale(.small).accessibilityHidden(true) }
                Text(data.left == 0 ? (data.waitlist > 0 ? "\(data.waitlist) waiting" : "Full")
                     : (dropIn ? "Drop-in · \(data.left) left" : "\(data.left) left"))
                    .contentTransition(.numericText())
            }
            .countFont(.caption, weight: .medium).foregroundStyle(low ? Color.statusWarning : Color.secondary)
        }
    }

    private func a11yLabel(_ s: ClassSession) -> String {
        "\(s.start.cpTimeShort), \(s.durationMin) minutes. \(s.name). \(s.category.title). Intensity \(s.intensity) of 5. \(data.coach.shortName), \(s.room). "
        + (data.left == 0 ? "Full" : "\(data.left) \(s.spotNoun) left")
    }
}

/// Compact card for "Today at this club" and "Also this week".
struct ClassCompactCard: View {
    var data: ClassRowData
    var showDate = false
    var body: some View {
        let s = data.session
        VStack(alignment: .leading, spacing: 6) {
            Text(showDate ? s.start.cpFormat("EEE") + " " + s.start.cpTimeShort : s.start.cpTimeShort).font(.headline).monospacedDigit()
            Text(s.name).font(.subheadline.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            CategoryBadge(category: s.category, compact: true)
            IntensityRibs(value: s.intensity, category: s.category)
            Text(data.left == 0 ? "Full" : "\(data.left) \(s.spotNoun) left").font(.caption).foregroundStyle(data.left > 0 && data.left <= 5 ? Color.statusWarning : Color.secondary)
        }
        .frame(width: 168, alignment: .leading)
        .cardStyle(padding: 12)
        .overlay(alignment: .top) { Rectangle().fill(s.category.color).frame(height: 4).clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)) }
        .accessibilityElement(children: .combine)
    }
}

/// A class with its category graphic on top. It draws no card of its own: put it in a list row with
/// `listRowInsets(EdgeInsets())`, so the row's background gives it the list's own card shape and corner radius.
struct ClassFeatureCard: View {
    var data: ClassRowData
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let s = data.session
        // At accessibility sizes the text wraps and the bottom line stacks, so nothing truncates.
        let lines = dts.isAccessibilitySize ? nil : 1
        let bottom = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 0) {
            // A 2:1 band the full width of the card, with the crop composed for that ratio.
            Color.clear
                .aspectRatio(2, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { ClassGraphic(category: s.category, variant: .card) }
                .clipped()
            // Name and coach on top; when and how many spots split to the two sides of the bottom line.
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.headline).lineLimit(lines)
                    Text(data.coach.shortName).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(lines)
                }
                bottom {
                    Text("\(s.start.cpWeekdayShort) \(s.start.cpTimeShort)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    if !dts.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(data.left == 0 ? "Full" : "\(data.left) left")
                        .countFont(.footnote, weight: .medium).foregroundStyle(data.left > 0 && data.left <= 5 ? Color.statusWarning : Color.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A booking row (class, court, lane, kids club, PT) in lists, as in the Coming up section on Today: the booking's
/// tile, its name, one line of when and where, and a trailing item (a pill, a button or the outcome).
struct BookingListRow<Trailing: View>: View {
    var booking: Booking
    var coach: Coach?
    /// When and where, already joined: "4 pm · Studio A", "Tue, Oct 20 · 6 am".
    var line: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            BookingTile(booking: booking, coach: coach, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                if !line.isEmpty {
                    Text(line).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(dts.isAccessibilitySize ? nil : 1)
                }
            }
            if !dts.isAccessibilitySize { Spacer(minLength: 8) }
            trailing
        }
        .frame(minHeight: 52)
    }
}

extension Booking {
    /// Where, for a row's second line: the room, court, lane or children. A training session's title names the
    /// coach already, so it adds nothing. The club shows only when the list is not about that club.
    func placeText(clubShort: String) -> String {
        let place = kind == .pt ? "" : detail
        return [place, clubShort].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Coach card

struct CoachCard: View {
    enum Variant { case row, card }
    var coach: Coach
    var variant: Variant = .row
    var body: some View {
        switch variant {
        case .row:
            HStack(spacing: 12) {
                CoachImage(name: coach.fullName, category: coach.category, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.fullName).font(.headline)
                    Text(coach.credential).font(.subheadline).foregroundStyle(Color.secondary)
                }
            }
            .frame(minHeight: 56)
            .accessibilityElement(children: .combine)
        case .card:
            VStack(alignment: .leading, spacing: 8) {
                CoachImage(name: coach.fullName, category: coach.category, size: 64)
                Text(coach.shortName).font(.headline)
                Text(coach.credential).font(.footnote).foregroundStyle(Color.secondary).lineLimit(2)
            }
            .frame(width: 150, alignment: .leading)
            .cardStyle(padding: 12)
            .accessibilityElement(children: .combine)
        }
    }
}
