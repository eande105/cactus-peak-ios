import SwiftUI

struct ClubCard: View {
    enum Variant { case listRow, compact, feature, mapCallout }
    var club: Club
    var reading: BusynessReading
    var now: Date
    var variant: Variant = .listRow
    var isHome = false
    var closest = false
    var selected = false
    /// Extra lines under the crowd level in the list row: one per area, then next open times.
    var details: [String] = []
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        switch variant {
        case .listRow: listRow
        case .compact: compact
        case .feature: feature
        case .mapCallout: callout
        }
    }

    /// Short row: name (house if home), open status and distance, crowd meter and level word on the trailing side.
    /// Areas and next-open lines moved to `ClubReserveSummary` (club detail). `details` is kept for source
    /// compatibility and is no longer drawn.
    private var listRow: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isHome { Image(systemName: "house.fill").imageScale(.small).foregroundStyle(Color.secondary).accessibilityLabel("Home club") }
                    Text(club.fullName).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))) {
                    OpenStatus(club: club, now: now)
                    Text("· " + String(format: "%.1f mi", club.distanceMiles)).font(.footnote).foregroundStyle(Color.secondary).monospacedDigit()
                    if closest { Text("Closest").font(.caption.weight(.semibold)).fixedSize().padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.primarySubtle, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Color.linkText) }
                }
            }
            if !dts.isAccessibilitySize {
                Spacer(minLength: 0)
                BusynessMeter(reading: reading, variant: .compact, now: now)
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.brandAccent).accessibilityHidden(true) }
            } else {
                BusynessMeter(reading: reading, variant: .compact, now: now)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ClubSet(slug: club.slug, size: 24).padding(.bottom, 4)
                Text(club.fullName).font(.headline).lineLimit(2)
                OpenStatus(club: club, now: now)
                BusynessMeter(reading: reading, variant: .inline, now: now)
            }.padding(12)
        }
        .frame(width: 230)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var feature: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ClubSet(slug: club.slug, size: 32).padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(club.fullName).brandFont(.title2)
                    Text(club.city).font(.subheadline).foregroundStyle(Color.secondary)
                }
                Text(club.personality).font(.subheadline).foregroundStyle(Color.secondary)
                BusynessMeter(reading: reading, variant: .inline, now: now)
            }.padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(club.fullName).font(.headline)
                OpenStatus(club: club, now: now)
                Text("Today \(club.opens(on: now) == 270 ? "4:30 am–10 pm" : "6 am–8 pm")").font(.footnote).foregroundStyle(Color.secondary)
                BusynessMeter(reading: reading, variant: .inline, now: now)
            }.padding(12)
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Map pin: club short name plus a compact rib meter. 44 pt target.
struct ClubPin: View {
    var club: Club
    var reading: BusynessReading
    var isSelected: Bool
    var isHome: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isHome { Image(systemName: "house.fill").imageScale(.small) }
                Text(club.shortName).font(.caption.weight(.semibold)).lineLimit(1)
                if reading.closed { Text("Closed").font(.caption2) } else if isSelected {
                    RibMeter(value: reading.level, tone: isSelected ? .onNight : reading.tone, size: .sm, peak: false)
                }
            }
            .foregroundStyle(isSelected ? Color.nightOnSurface : (reading.closed ? Color.secondary : Color.primary))
            .padding(.horizontal, 10).frame(minHeight: 32)
            .background(isSelected ? Color.nightSurface : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? Color.brandAccent : Color(.opaqueSeparator), lineWidth: isSelected ? 2 : 1))
            Image(systemName: "arrowtriangle.down.fill").font(.caption2).foregroundStyle(isSelected ? Color.nightSurface : Color(.opaqueSeparator)).offset(y: -2)
        }
        .frame(minWidth: 44, minHeight: 44)
        // Map labels share a small space, so their text stops growing at xxxLarge; the list rows carry the full size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(club.fullName), \(reading.closed ? "closed" : reading.word)")
    }
}

struct HoursTable: View {
    var club: Club
    var now: Date
    var body: some View {
        let days = (0..<7).map { now.startOfAZDay.addingDays($0) }
        ForEach(days, id: \.self) { d in
            let isToday = AZ.cal.isDate(d, inSameDayAs: now)
            let weekend = AZ.cal.isDateInWeekend(d)
            LabeledContent {
                Text(weekend ? "6 am–8 pm" : "4:30 am–10 pm").monospacedDigit()
            } label: {
                HStack(spacing: 6) {
                    if isToday { Circle().fill(club.isOpen(at: now) ? Color.statusSuccess : Color.secondary).frame(width: 8, height: 8).accessibilityHidden(true) }
                    Text(d.cpFormat("EEEE"))
                    if isToday { Text("Today").font(.caption.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 1).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4)) }
                }
            }
            .fontWeight(isToday ? .semibold : .regular)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The current club control. Today and Book use it, so the club choice looks the same on both.
struct ClubPill: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var showCrowd = true

    var body: some View {
        let club = model.club(model.currentClubID)
        Button { router.present(.clubSwitcher(.viewing)) } label: {
            HStack(spacing: 8) {
                Text(club.shortName).font(.subheadline.weight(.semibold)).lineLimit(1)
                if showCrowd { BusynessMeter(reading: model.busyness(club), variant: .compact, now: model.now) }
                Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
            }
            .foregroundStyle(Color.primary)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Club: \(club.fullName). Change club")
    }
}

/// The current club as a standard glass toolbar button with a standard menu. Today and Book use it in place of
/// the title. The menu lists every club by name with its crowd word; picking one switches to it. No item has an
/// icon or a checkmark: the button already names the current club.
struct ClubMenuButton: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        let club = model.club(model.currentClubID)
        Menu {
            Section {
                ForEach(model.clubs) { c in
                    let reading = model.busyness(c)
                    Button { select(c.id) } label: {
                        Text(c.shortName)
                        Text(reading.closed ? "Closed" : reading.word)
                    }
                }
            }
            Button("All clubs") { router.present(.clubSwitcher(.viewing)) }
        } label: {
            Text(club.shortName).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize()
        }
        .barItem()
        .accessibilityLabel("Club: \(club.fullName)")
        .accessibilityHint("Change club")
    }

    /// Does what `ClubSwitcherSheet(mode: .viewing)` does: set `currentClubID`, and fall back to a sport the club
    /// has courts for.
    private func select(_ id: ClubID) {
        guard let c = model.clubs.first(where: { $0.id == id }) else { return }
        model.currentClubID = c.id
        if c.courts(for: router.sport) == 0, let sp = c.courtSports.first { router.sport = sp }
    }
}

/// The lines that used to sit under a club list row, for club detail: one "<area> · Usually <word>" line per area,
/// then the next open time for courts, lap lanes and kids club.
struct ClubReserveSummary: View {
    @Environment(AppModel.self) private var model
    var club: Club

    /// Same text the Clubs list passed as `details:`.
    static func lines(_ c: Club, model: AppModel) -> [String] {
        let areas = model.areas(c).map { "\($0.label) · \(CrowdText.usually(level: model.areaCrowd($0, at: model.now).level))" }
        let open = ReserveKind.allCases.compactMap { model.nextOpenLine($0, club: c) }
        return areas + open
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.lines(club, model: model), id: \.self) {
                Text($0).font(.subheadline).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One sauna, recovery, pool or therapy pool area: icon, label, crowd meter and the typical level at the hour.
/// There is no reserve control on an area.
struct AreaCrowdRow: View {
    @Environment(AppModel.self) private var model
    var area: ClubArea
    var body: some View {
        let c = model.areaCrowd(area, at: model.now)
        HStack(spacing: 12) {
            Image(systemName: area.area.symbol).frame(width: 28).foregroundStyle(Color.primary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.label).font(.headline)
                Text(CrowdText.usually(level: c.level, at: model.now)).font(.footnote).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            RibMeter(value: c.level, tone: .crowd(c.level), size: .sm, peak: false)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}
