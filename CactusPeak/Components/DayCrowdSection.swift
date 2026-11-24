import SwiftUI

/// The selected day's crowd at the current club, like the hourly forecast in Apple Weather: one line that sums up
/// the day, then an hour-by-hour strip of bars from opening to close. Today starts at "Now" with the live reading;
/// other days show the usual crowd for that weekday.
struct DayCrowdSection: View {
    @Environment(AppModel.self) private var model
    var day: Date

    var body: some View {
        let club = model.club(model.currentClubID)
        let isToday = AZ.cal.isDate(day, inSameDayAs: model.now)
        let reading = model.busyness(club)
        let hours = hours(club, isToday: isToday)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "person.2.fill").accessibilityHidden(true)
                    Text("Crowd")
                    Spacer(minLength: 8)
                    if isToday && !reading.closed {
                        Text("\(reading.word) now").foregroundStyle(Color.primary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandSecondary)
                Text(summary(club, hours: hours, isToday: isToday, reading: reading))
                    .font(.subheadline).foregroundStyle(Color.secondary)
                if !hours.isEmpty {
                    Divider()
                    ScrollView(.horizontal) {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(hours, id: \.self) { h in bar(h, club: club, now: isToday && h == hours.first) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // The strip runs to the card's edges and scrolls under them, like the hourly forecast in Weather.
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                    .padding(.horizontal, -20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hours.map { "\(label($0, now: false)), \(BusynessReading.word(club.typicalLevel(at: $0)))" }.joined(separator: ". "))
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One bar per hour: its height is the usual level (1 to 5), the current hour in full colour and the busy hours
    /// in the warning colour.
    private func bar(_ h: Date, club: Club, now: Bool) -> some View {
        let level = now ? model.busyness(club).level : club.typicalLevel(at: h)
        let tint: Color = level >= 4 ? Color.statusWarning : Color.brandSecondary
        return VStack(spacing: 6) {
            Capsule()
                .fill(now ? tint : tint.opacity(0.35))
                .frame(width: 12, height: CGFloat(10 + level * 9))
            Text(label(h, now: now))
                .font(.caption2.weight(now ? .bold : .regular))
                .foregroundStyle(now ? Color.primary : Color.secondary)
                .lineLimit(1).fixedSize()
        }
        .frame(minWidth: 40)
    }

    private func label(_ h: Date, now: Bool) -> String { now ? "Now" : h.cpTimeShort }

    /// The open hours of the day, on the hour. Today starts at the current hour.
    private func hours(_ club: Club, isToday: Bool) -> [Date] {
        let start = club.opens(on: day) / 60
        let end = (club.closes(on: day) - 1) / 60
        var first = start
        if isToday { first = max(start, AZ.cal.component(.hour, from: model.now)) }
        guard first <= end else { return [] }
        return (first...end).compactMap { AZ.cal.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
    }

    private func summary(_ club: Club, hours: [Date], isToday: Bool, reading: BusynessReading) -> String {
        guard let peak = hours.max(by: { club.typicalLevel(at: $0) < club.typicalLevel(at: $1) }) else {
            return "Closed for the day. Opens \(reading.opensText.replacingOccurrences(of: ":00", with: ""))."
        }
        let when = isToday ? "" : " on \(day.cpFormat("EEEE"))s"
        return "Usually busiest at \(peak.cpTimeShort)\(when).".replacingOccurrences(of: "..", with: ".")
    }
}
