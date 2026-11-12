import XCTest
@testable import CactusPeak

/// Expected values come from web-app/lib/data/sessions.ts (`hash` and `sessionsForDay`). Recomputed on 2026-11-02, when
/// the club slugs became cross streets: the slug is part of the hashed session key, so every formula value moved.
final class SessionBaselineTests: XCTestCase {
    func testHashMatchesWeb() {
        XCTAssertEqual(SessionBaseline.hash("dobson-southern|2026-10-27|09:30|dfy"), 0.23926, accuracy: 1e-12)
    }

    func testJSRoundRoundsHalfUp() {
        XCTAssertEqual(SessionBaseline.jsRound(10.5), 11)
        XCTAssertEqual(SessionBaseline.jsRound(11.5), 12)
        XCTAssertEqual(SessionBaseline.jsRound(10.49), 10)
    }

    func testBaselinesMatchWeb() {
        let cases: [(club: String, day: String, time: String, key: String, cap: Int, booked: Int, wait: Int)] = [
            ("dobson-southern", "2026-10-27", "09:30", "dfy", 20, 9, 0),         // formula
            ("dobson-southern", "2026-10-28", "05:30", "ms", 12, 4, 0),          // formula
            ("val-vista-warner", "2026-10-29", "06:00", "rrs", 14, 14, 3),  // STORY, with waitlist
            ("dobson-southern", "2026-10-31", "08:00", "e60", 18, 15, 0),        // STORY
            ("dobson-southern", "2026-11-04", "11:00", "m30", 24, 24, 1),        // r > 0.93: full, waitlist
            ("dobson-southern", "2026-10-28", "09:00", "af", 16, 16, 2),         // r > 0.93
        ]
        for c in cases {
            let b = SessionBaseline.make(club: c.club, day: c.day, time: c.time, classKey: c.key, capacity: c.cap)
            XCTAssertEqual(b.booked, c.booked, "\(c.club) \(c.day) \(c.time) \(c.key)")
            XCTAssertEqual(b.waitlist, c.wait, "\(c.club) \(c.day) \(c.time) \(c.key)")
        }
    }

    @MainActor func testSpotsLeftMatchesWebSessionLeft() {
        let m = Fixtures.model()
        m.applyHousehold(Fixtures.household(bookings: []), savedAt: Date())
        // Fixture Climb Cycle, Wed Oct 28 6:00 at Dobson & Southern, capacity 20. Web baseline: 11 booked.
        let s = m.session("dobson-southern~2026-10-28~0600~cc")!
        XCTAssertEqual(s.baseBooked, 11)
        XCTAssertEqual(m.spotsLeft(s), 9)
        // Two other households hold spots.
        m.applyCounts([SessionCountRow(sessionId: s.id, booked: 2, waitlisted: 0)])
        XCTAssertEqual(m.spotsLeft(s), 7)
        // This member books: counted once, whether or not session_counts has caught up.
        guard case .ok = m.book(s) else { return XCTFail("Book failed") }
        XCTAssertEqual(m.spotsLeft(s), 6)
        m.applyCounts([SessionCountRow(sessionId: s.id, booked: 3, waitlisted: 0)])
        XCTAssertEqual(m.spotsLeft(s), 6)
    }
}
