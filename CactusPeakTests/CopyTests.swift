import XCTest
@testable import CactusPeak

@MainActor
final class CopyTests: XCTestCase {
    func testEndingSentence() {
        XCTAssertEqual("5:30 am".endingSentence, "5:30 am.")
        XCTAssertEqual("Back at 6 pm.".endingSentence, "Back at 6 pm.")
        XCTAssertEqual("Free cancel".endingSentence, "Free cancel.")
        XCTAssertEqual("Ready?".endingSentence, "Ready?")
    }

    func testTimeFormatter() {
        XCTAssertEqual(AZ.date(2026, 10, 27, 5, 30).cpTime, "5:30 am")
        XCTAssertEqual(AZ.date(2026, 10, 27, 12, 0).cpTime, "12:00 pm")
        XCTAssertEqual(AZ.date(2026, 10, 27, 0, 5).cpTime, "12:05 am")
        XCTAssertEqual(AZ.date(2026, 10, 27, 6, 0).cpTimeShort, "6 am")
        XCTAssertEqual(AZ.date(2026, 10, 27, 18, 15).cpTimeShort, "6:15 pm")
        XCTAssertEqual(AZ.date(2026, 10, 27, 6, 0).cpClock.0, "6:00")
    }

    /// Every generated sentence must be free of a doubled period. Times carry no period, so a sentence adds one only once.
    func testNoDoublePeriods() {
        let m = Fixtures.model()
        m.applyHousehold(Fixtures.household(bookings: [Fixtures.booking("b1")]), savedAt: Date())
        var texts: [String] = []
        for c in m.clubs { texts.append(m.popularCaption(c)) }
        for b in m.upcomingBookings { texts.append("Free cancel until \(b.cancelCutoff().cpTime)") }
        texts.append(ClashPrompt(id: "x", existing: "Rib Rack Strength", existingTime: "5:30 am").message)
        for t in texts { XCTAssertFalse(t.contains(".."), "Double period in: \(t)") }
    }
}
