import Foundation

/// What the pool is like now, for the Today stat cards. Demo data: the water temperature is a fixed reading per club,
/// taken at the top of the hour, and the shade sails follow a fixed daily schedule.
struct PoolConditions: Hashable, Sendable {
    /// The lap pool's water temperature, in °F.
    var waterF: Int
    /// When the reading was taken.
    var readAt: Date
    /// Nil at clubs without shade sails.
    var shade: ShadeSails?
    /// The lanes free in the lane slot under way now. Nil when the pool is closed.
    var lanesOpen: Int?
    var laneCount: Int
    /// When lane swim next opens, while the pool is closed.
    var opens: Date?
}

/// The outdoor pool's shade sails: up through the middle of the day, down in the morning and evening.
struct ShadeSails: Hashable, Sendable {
    static let upHour = 9
    static let downHour = 17
    var up: Bool
    /// When the sails next change: down when up, up when down.
    var next: Date
}

extension AppModel {
    /// Nil when the club has no pool.
    func poolConditions(_ club: Club) -> PoolConditions? {
        guard club.hasPool else { return nil }
        let water = club.slug == "dobson-southern" ? 83 : club.slug == "val-vista-warner" ? 81 : 82
        let readAt = AZ.cal.dateInterval(of: .hour, for: now)?.start ?? now
        let slots = laneSlots(club: club, day: now.startOfAZDay)
        let current = slots.first { $0.start <= now && now < $0.start.addingTimeInterval(45 * 60) }
        let opens = current == nil ? (slots.first { $0.start > now }?.start ?? laneSlots(club: club, day: now.startOfAZDay.addingDays(1)).first?.start) : nil
        return PoolConditions(waterF: water, readAt: readAt, shade: club.slug == "power-mckellips" ? shadeSails(at: now) : nil,
                              lanesOpen: current?.open, laneCount: club.lanes, opens: opens)
    }

    private func shadeSails(at date: Date) -> ShadeSails {
        let day = date.startOfAZDay
        let up = AZ.cal.date(bySettingHour: ShadeSails.upHour, minute: 0, second: 0, of: day)!
        let down = AZ.cal.date(bySettingHour: ShadeSails.downHour, minute: 0, second: 0, of: day)!
        if date < up { return ShadeSails(up: false, next: up) }
        if date < down { return ShadeSails(up: true, next: down) }
        return ShadeSails(up: false, next: up.addingDays(1))
    }
}
