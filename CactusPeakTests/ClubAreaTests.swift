import XCTest
@testable import CactusPeak

@MainActor
final class ClubAreaTests: XCTestCase {
    /// Rows shaped as PostgREST returns them. Weekday and weekend differ at every hour, so a mixed-up day type fails a test.
    static let areasJSON = """
    [{"club_slug":"dobson-southern","area":"sauna","label":"Sauna","sort":1,
      "typical_weekday":[1,1,2,2,3,3,3,4,4,4,5,5,5,4,3,2,1,1],
      "typical_weekend":[2,2,2,3,3,3,3,3,3,3,3,3,3,3,3,2,2,2]},
     {"club_slug":"dobson-southern","area":"therapy_pool","label":"Therapy pool","sort":0,
      "typical_weekday":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2],
      "typical_weekend":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]},
     {"club_slug":"gilbert-page","area":"recovery","label":"Recovery lounge","sort":0,
      "typical_weekday":[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],"typical_weekend":[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3]}]
    """

    private func rows() -> [ClubAreaRow] { Fixtures.decode(Self.areasJSON, as: [ClubAreaRow].self) }
    private func sauna() -> ClubArea { CatalogMapper.areas(rows())["dobson-southern"]!.first { $0.area == .sauna }! }

    // Tue Oct 27, 2026 is a weekday. Sat Oct 31, 2026 is a weekend.
    private let weekday = AZ.date(2026, 10, 27)
    private let weekend = AZ.date(2026, 10, 31)

    func testRowDecodesFromSnakeCaseJSON() {
        let r = rows()
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0].clubSlug, "dobson-southern")
        XCTAssertEqual(r[0].area, "sauna")
        XCTAssertEqual(r[0].label, "Sauna")
        XCTAssertEqual(r[0].typicalWeekday.count, 18)
        XCTAssertEqual(r[0].typicalWeekend, [2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2])
    }

    func testMappingGroupsByClubAndSorts() {
        let map = CatalogMapper.areas(rows())
        XCTAssertEqual(map["dobson-southern"]?.map(\.area), [.therapyPool, .sauna], "Sorted by `sort`")
        XCTAssertEqual(map["gilbert-page"]?.map(\.area), [.recovery])
        XCTAssertNil(map["main-center"])
    }

    func testUnknownAreaKindIsSkipped() {
        var r = rows()
        r.append(ClubAreaRow(clubSlug: "x", area: "steam_room", label: "Steam", sort: 0, typicalWeekday: [], typicalWeekend: []))
        XCTAssertNil(CatalogMapper.areas(r)["x"])
    }

    func testCatalogRowsFromOlderCacheWithoutAreas() throws {
        let json = #"{"clubs":[],"categories":[],"coaches":[],"classTypes":[],"schedules":[],"plans":[],"ptPacks":[],"faqs":[]}"#
        let c = try JSONDecoder().decode(CatalogRows.self, from: Data(json.utf8))
        XCTAssertTrue(c.clubAreas.isEmpty)
    }

    func testWeekdayAndWeekendUseDifferentArrays() {
        let a = sauna()
        // 1 pm is index 9: weekday 4, weekend 3.
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 13, 0)).level, 4)
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 31, 13, 0)).level, 3)
        // 7 am is index 3: weekday 2, weekend 3.
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 7, 0)).level, 2)
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 31, 7, 0)).level, 3)
    }

    func testEdgesAt4amAnd9pm() {
        let a = sauna()
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 4, 0)).level, 1, "4 am is index 0")
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 21, 0)).level, 1, "9 pm is index 17")
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 31, 4, 59)).level, 2)
        // Outside the 18 hours the nearest end is used.
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 2, 0)).level, 1)
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 23, 0)).level, 1)
        let tp = CatalogMapper.areas(rows())["dobson-southern"]!.first { $0.area == .therapyPool }!
        XCTAssertEqual(tp.crowd(at: AZ.date(2026, 10, 27, 21, 0)).level, 2)
    }

    func testWordMapping() {
        let words = (1...5).map { BusynessReading.word($0) }
        XCTAssertEqual(words, ["Quiet", "Light", "Steady", "Busy", "Packed"])
        // Sauna weekday: 5 pm index 13 = 4 (Busy); 11 am index 7 = 4; 2 pm index 10 = 5 (Packed).
        XCTAssertEqual(sauna().crowd(at: AZ.date(2026, 10, 27, 17, 0)).word, "Busy")
        XCTAssertEqual(sauna().crowd(at: AZ.date(2026, 10, 27, 14, 0)).word, "Packed")
        XCTAssertEqual(sauna().crowd(at: AZ.date(2026, 10, 27, 5, 0)).word, "Quiet")
    }

    func testNoRandomness() {
        let a = sauna()
        let d = AZ.date(2026, 10, 27, 13, 20)
        let first = a.crowd(at: d)
        for _ in 0..<20 { XCTAssertEqual(a.crowd(at: d).level, first.level) }
        XCTAssertEqual(a.crowd(at: AZ.date(2026, 10, 27, 13, 0)).level, a.crowd(at: AZ.date(2026, 10, 27, 13, 59)).level, "Same hour, same level")
    }

    func testBadArrayFallsBackToLight() {
        let a = ClubArea(clubID: "x", area: .sauna, label: "Sauna", sort: 0, typicalWeekday: [], typicalWeekend: [])
        XCTAssertEqual(a.crowd(at: weekday).level, 2)
    }

    func testModelAreaCrowdMatchesAndExposesAreasPerClub() {
        let m = Fixtures.model()
        var rows = Fixtures.catalog
        rows.clubAreas = self.rows()
        m.applyCatalog(rows, savedAt: Date())
        let club = m.club("dobson-southern")
        XCTAssertEqual(m.areas(club).map(\.label), ["Therapy pool", "Sauna"])
        let a = m.areas(club)[1]
        let d = AZ.date(2026, 10, 27, 13, 0)
        XCTAssertEqual(m.areaCrowd(a, at: d).level, 4)
        XCTAssertEqual(m.areaCrowd(a, at: d).word, "Busy")
    }

    func testClubTypicalLevelUsesSameHourIndex() {
        let c = CatalogMapper.clubs(Fixtures.catalog.clubs)[0]
        // typical_weekday starts 1,2,3,4,3,3,3,2,3,2,2,3,4,5,4,3,2,1; 5 pm is index 13 = 5.
        XCTAssertEqual(c.typicalLevel(at: AZ.date(2026, 10, 27, 17, 0)), 5)
        // typical_weekend: 5 pm is index 13 = 2.
        XCTAssertEqual(c.typicalLevel(at: AZ.date(2026, 10, 31, 17, 0)), 2)
    }

    func testCrowdCopySaysUsuallyNeverNow() {
        XCTAssertEqual(CrowdText.usually(level: 4, at: AZ.date(2026, 10, 27, 18, 15)), "Usually busy at 6 pm")
        XCTAssertEqual(CrowdText.usually(level: 1, at: AZ.date(2026, 10, 27, 4, 30)), "Usually quiet at 4 am")
        XCTAssertEqual(CrowdText.usually(level: 5), "Usually packed")
    }

    func testBookedToastText() {
        var b = Booking(id: "b", kind: .court, status: .booked, sessionID: nil, title: "Pickleball · Court 3", clubID: "dobson-southern",
                        category: .court, start: AZ.date(2026, 10, 29, 18, 0), end: AZ.date(2026, 10, 29, 19, 30), detail: "Court 3")
        XCTAssertEqual(AppModel.bookedToastText(b), "Booked · Pickleball · Court 3 · Thu 6 pm")
        b.kind = .kids; b.title = "Kids club"; b.detail = "Mia + Eli"
        XCTAssertEqual(AppModel.bookedToastText(b), "Booked · Kids club · Mia + Eli · Thu 6 pm")
    }
}
