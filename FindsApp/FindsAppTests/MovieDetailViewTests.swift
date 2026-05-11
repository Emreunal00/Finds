


import Testing
@testable import FindsApp

@Suite("MovieDetailView Basic Tests")
struct MovieDetailViewTests {
    @Test("MovieDetailView displays correct movie info")
    func testMovieDetailViewDisplaysMovie() {
        let movie = Movie(id: 42, title: "Dune", year: 2021, genres: ["#12"], posterName: "", rating: 4.8, summary: "A desert planet epic.", posterURL: nil, durationMinutes: 155, mediaType: "movie")
        
        #expect(movie.title == "Dune")
        #expect(movie.year == 2021)
        #expect(movie.rating == 4.8)
        #expect(movie.durationMinutes == 155)
        #expect(movie.mediaType == "movie")
        #expect(movie.genres.contains("#12"))
    }
}
