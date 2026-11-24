import SwiftUI

/// The Book page's controls under the day strip, like the option chips under the mode picker in Apple Maps
/// Directions ("Now ⌄", "Prefer ⌄"). The first chip picks what to book; the chips after it change with that choice and
/// hold only the controls people use most. Everything else waits in the Filters sheet (progressive disclosure).
struct BookControlBar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView(.horizontal) {
            // One container, so the glass chips share one sampling pass and blend when they sit close.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    typeChip
                    switch router.segment {
                    case .classes: classChips
                    case .courts: courtChips
                    case .lanes, .kids: EmptyView()
                    }
                }
                // Room for the glass shadow inside the scroll view.
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.horizontal, BookHeader.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: router.segment)
    }

    // MARK: What to book

    private var typeChip: some View {
        @Bindable var router = router
        return Menu {
            Picker("Book", selection: $router.segment) {
                ForEach(BookSegment.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            BookChip(title: router.segment.rawValue, symbol: router.segment.symbol, menu: true, prominent: true)
        }
        .bookChipStyle()
        .accessibilityLabel("Book \(router.segment.rawValue)")
    }

    // MARK: Classes: time of day, spots open, then the rest in the sheet

    @ViewBuilder private var classChips: some View {
        @Bindable var router = router
        let times = router.filters.times
        Menu {
            Button { router.filters.times = [] } label: {
                if times.isEmpty { Label("Any time", systemImage: "checkmark") } else { Text("Any time") }
            }
            Section {
                ForEach(TimeOfDay.allCases) { t in
                    Toggle(isOn: Binding(get: { times.contains(t) },
                                         set: { on in if on { router.filters.times.insert(t) } else { router.filters.times.remove(t) } })) {
                        Label(t.rawValue, systemImage: t.symbol)
                        Text(t.detail)
                    }
                }
            }
        } label: {
            BookChip(title: timeTitle(times), symbol: nil, menu: true)
        }
        .bookChipStyle(selected: !times.isEmpty)
        Button { router.filters.spotsOnly.toggle() } label: {
            BookChip(title: "Spots open", symbol: router.filters.spotsOnly ? "checkmark" : nil)
        }
        .bookChipStyle(selected: router.filters.spotsOnly)
        Button { router.present(.filters) } label: {
            BookChip(title: moreCount > 0 ? "More · \(moreCount)" : "More filters", symbol: "line.3.horizontal.decrease")
        }
        .bookChipStyle(selected: moreCount > 0)
        .accessibilityValue(router.filters.activeCount > 0 ? "\(router.filters.activeCount) filters on" : "none on")
    }

    /// Filters that live only in the sheet: what the chips above do not show.
    private var moreCount: Int {
        var f = router.filters
        f.times = []; f.spotsOnly = false
        return f.activeCount
    }

    private func timeTitle(_ times: Set<TimeOfDay>) -> String {
        switch times.count {
        case 0: "Any time"
        case 1: times.first!.rawValue
        default: "\(times.count) times"
        }
    }

    // MARK: Courts: sport and length

    @ViewBuilder private var courtChips: some View {
        @Bindable var router = router
        let sports = model.club(model.currentClubID).courtSports
        if sports.count > 1 {
            Menu {
                Picker("Sport", selection: $router.sport) { ForEach(sports) { Text($0.title).tag($0) } }.pickerStyle(.inline)
            } label: { BookChip(title: router.sport.title, symbol: nil, menu: true) }
            .bookChipStyle()
        }
        Menu {
            Picker("Length", selection: $router.duration) { ForEach([60, 90], id: \.self) { Text("\($0) minutes").tag($0) } }.pickerStyle(.inline)
        } label: { BookChip(title: "\(router.duration) min", symbol: nil, menu: true) }
        .bookChipStyle()
    }
}

/// One chip's label: an optional symbol, the title, and a chevron when it opens a menu. The glass button style
/// (`bookChipStyle`) draws the capsule.
struct BookChip: View {
    var title: String
    var symbol: String?
    var menu = false
    /// The first chip, which picks what to book: it reads a little stronger than the options after it.
    var prominent = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            Text(title).lineLimit(1)
            if menu { Image(systemName: "chevron.down").imageScale(.small).fontWeight(.semibold).accessibilityHidden(true) }
        }
        .font(.subheadline.weight(prominent ? .semibold : .medium))
    }
}

extension View {
    /// A Book chip is a glass capsule button. A chip that is on is prominent glass in the brand accent, so an
    /// active filter reads at a glance, as the selected option chips do in Apple Maps.
    @ViewBuilder func bookChipStyle(selected: Bool = false) -> some View {
        if selected {
            accentProminent().accessibilityAddTraits(.isSelected)
        } else {
            buttonStyle(.glass).tint(Color.primary)
        }
    }
}

/// The graphical calendar for days past the strip, shown as a popover from the toolbar's calendar button.
struct BookCalendarPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var router = router
        let kind: ReserveKind = router.segment == .courts ? .court : .kidsClub
        let last = model.reserveDays(kind).last ?? model.now
        DatePicker("Day", selection: $router.day, in: model.now.startOfAZDay...last, displayedComponents: .date)
            .datePickerStyle(.graphical)
            // The bar button's tint is .primary; the calendar's selected day takes the brand accent instead.
            .tint(Color.brandAccent)
            .environment(\.timeZone, AZ.tz).environment(\.calendar, AZ.cal)
            .frame(width: 320)
            .padding(8)
            // Picking a day is the whole task, so the popover closes on it.
            .onChange(of: router.day) { dismiss() }
            .presentationCompactAdaptation(.popover)
    }
}

extension BookSegment {
    var symbol: String {
        switch self {
        case .classes: "figure.mixed.cardio"
        case .courts: "figure.pickleball"
        case .lanes: "figure.pool.swim"
        case .kids: "figure.and.child.holdinghands"
        }
    }
}

extension TimeOfDay {
    var symbol: String {
        switch self {
        case .early: "sunrise"
        case .morning: "sun.min"
        case .midday: "sun.max"
        case .evening: "sunset"
        }
    }
}
