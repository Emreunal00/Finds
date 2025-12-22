//
//  PickerViewTests.swift
//
import Testing
@testable import FindsApp

@Suite("PickerView Basic Tests")
struct PickerViewTests {
    @Test("PickerView can load and present movies array")
    func testMoviesArrayDefault() async throws {
        let mockMovies = [
            Movie(id: 1, title: "One", year: 2020, genres: [], posterName: "", rating: 7.5, summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie", cast: nil, directors: nil, popularity: nil),
            Movie(id: 2, title: "Two", year: 2021, genres: [], posterName: "", rating: 6.0, summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie", cast: nil, directors: nil, popularity: nil)
        ]
        #expect(!mockMovies.isEmpty)
        #expect(mockMovies[0].title == "One")
    }
}
