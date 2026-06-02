


import Testing
@testable import FindsApp

@Suite("Rating System Basic Tests")
struct RatingSystemTests {
    @Test("Local rating assignment and equatable")
    func testRatingAssignment() {
        let rating1: Double = 4.0
        let rating2: Double = 3.5
        #expect(rating1 != rating2)
        #expect(rating1 > rating2)
        var ratings = ["user1": rating1]
        ratings["user1"] = rating2
        #expect(ratings["user1"] == 3.5)
    }
}
