import SwiftUI
import MapKit

/// Clubs tab: a map of the clubs, as Maps shows search results over the map, amenity tiles that filter the list,
/// then every club, nearest first.
/// Search matches a city, a ZIP, a cross street or an address, and shows the results alone. A row pushes the club's
/// page (`ClubDetailView`), which has the map.
struct ClubsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filters: Set<String> = []

    private let filterNames = ["Open now", "Pool", "Courts", "Kids club", "Recovery"]

    private func matches(_ c: Club, _ f: String) -> Bool {
        switch f {
        case "Open now": c.isOpen(at: model.now)
        case "Pool": c.hasPool
        case "Courts": c.hasCourts
        case "Kids club": c.hasKids
        case "Recovery": c.hasRecovery
        default: true
        }
    }

    private var shown: [Club] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.clubs.filter { c in
            let matchesQuery = q.isEmpty || c.zip.hasPrefix(q) || c.city.lowercased().contains(q) || c.area.lowercased().contains(q)
                || c.fullName.lowercased().contains(q) || c.address.lowercased().contains(q)
            return matchesQuery && filters.allSatisfy { matches(c, $0) }
        }
        .sorted { $0.distanceMiles < $1.distanceMiles }
    }

    var body: some View {
        let clubs = shown
        let browsing = query.trimmingCharacters(in: .whitespaces).isEmpty
        List {
            if browsing {
                ClubsMapSection(clubs: clubs.isEmpty ? model.clubs : clubs)
                CardStripSection(items: filterNames.map(AmenityFilter.init), count: 5, span: 2) {
                    DetailSectionHeader(title: "Amenities")
                } card: { f in
                    let on = filters.contains(f.name)
                    let n = model.clubs.filter { matches($0, f.name) }.count
                    ExploreTile(title: f.name, detail: n == 1 ? "1 club" : "\(n) clubs", tint: Color.brandAccent, textTint: Color.linkText, selected: on) {
                        if on { filters.remove(f.name) } else { filters.insert(f.name) }
                    } art: {
                        f.art
                    }
                }
            }
            if clubs.isEmpty && browsing {
                Section {
                    ContentUnavailableView {
                        Label("No club has all of those", systemImage: "mappin.slash")
                    } actions: {
                        Button("Clear filters") { filters = [] }
                    }
                }
                .listRowBackground(Color.clear)
            } else if !clubs.isEmpty {
                Section {
                    ForEach(clubs) { c in
                        NavigationLink(value: AppRoute.club(c.id)) {
                            ClubCard(club: c, reading: model.busyness(c), now: model.now, variant: .listRow, isHome: c.id == model.member.homeClubID)
                        }
                    }
                } header: {
                    if browsing { DetailSectionHeader(title: filters.isEmpty ? "All clubs" : "Matching clubs", detail: clubs.count == 1 ? "1 club" : "\(clubs.count) clubs") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        // The first section starts close under the search field.
        .contentMargins(.top, 8, for: .scrollContent)
        .overlay {
            // While browsing, the tiles stay on screen so a filter can be turned off where it was turned on.
            if clubs.isEmpty && !browsing { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle("Clubs")
        // A smaller title on the leading edge of the bar, in line with the filter button.
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City or ZIP")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(filterNames, id: \.self) { n in
                        Toggle(n, isOn: Binding(get: { filters.contains(n) }, set: { on in if on { filters.insert(n) } else { filters.remove(n) } }))
                    }
                    if !filters.isEmpty { Button("Clear filters") { filters = [] } }
                } label: {
                    Image(systemName: filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .barItem()
                .accessibilityLabel("Filters").accessibilityValue(filters.isEmpty ? "none on" : "\(filters.count) on")
            }
        }
    }
}

/// Every club on one map, the home club in the brand accent, as Maps shows results on the map above the list.
/// The map fits all pins and takes no pan or zoom, so the list scrolls freely; a tap on a pin opens that club.
private struct ClubsMapSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var clubs: [Club]
    @State private var selected: ClubID?

    var body: some View {
        Section {
            Map(initialPosition: .automatic, interactionModes: [], selection: $selected) {
                ForEach(clubs) { c in
                    let home = c.id == model.member.homeClubID
                    Marker(c.shortName, image: "RibPeakMark", coordinate: c.coordinate)
                        .tint(home ? Color.brandAccent : Color.brandSecondary)
                        .tag(c.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 240)
            .listRowInsets(EdgeInsets())
            .onChange(of: selected) { _, id in
                guard let id else { return }
                router.push(.club(id))
                selected = nil
            }
            .accessibilityLabel("Map of \(clubs.count) clubs")
        }
    }
}

/// One amenity filter for the Clubs tiles, with its brand object (a clock for Open now).
private struct AmenityFilter: Identifiable {
    var name: String
    var id: String { name }
    @MainActor @ViewBuilder var art: some View {
        switch name {
        case "Pool": SpaceGraphic(id: .lapPool)
        case "Courts": SpaceGraphic(id: .courts)
        case "Kids club": SpaceGraphic(id: .kidsClub)
        case "Recovery": SpaceGraphic(id: .recovery)
        default: Image(systemName: "clock").symbolFont(.system(size: 30, weight: .semibold)).foregroundStyle(Color.linkText)
        }
    }
}
