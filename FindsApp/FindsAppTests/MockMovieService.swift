







import Foundation
@testable import FindsApp

struct MockMovieService: MovieServicing {
    var genresToReturn: [TMDBGenre] = []
    var searchResults: [Movie] = []
    var discoverResults: [Movie] = []
    var errorToThrow: Error?
    
    
    var trendingResults: [Movie] { searchResults }
    var suggestionResults: [Movie] { searchResults }
    var trendingTVResults: [Movie] { searchResults }
    var suggestionTVResults: [Movie] { searchResults }
    
    func getTrending(page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        return searchResults
    }

    func getSuggestions(page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        return searchResults
    }

    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var items = searchResults
        if let year = year { items = items.filter { $0.year == year } }
        if let gid = genreID { items = items.filter { $0.genres.contains("#\(gid)") } }
        return items
    }

    func fetchGenres() async throws -> [TMDBGenre] {
        if let e = errorToThrow { throw e }
        return genresToReturn
    }

    func searchMulti(query: String, page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return searchResults
    }

    func fetchMovieRuntime(id: Int) async throws -> Int? {
        if let e = errorToThrow { throw e }
        return nil
    }

    func fetchTVRuntime(id: Int) async throws -> Int? {
        if let e = errorToThrow { throw e }
        return nil
    }

    func fetchMovieBasic(id: Int) async throws -> Movie {
        if let e = errorToThrow { throw e }
        return Movie(id: id, title: "Movie #\(id)", year: 0, genres: [], posterName: "", rating: 0, summary: "", posterURL: nil, durationMinutes: nil, mediaType: "movie")
    }

    func fetchTVBasic(id: Int) async throws -> Movie {
        if let e = errorToThrow { throw e }
        return Movie(id: id, title: "TV #\(id)", year: 0, genres: [], posterName: "", rating: 0, summary: "", posterURL: nil, durationMinutes: nil, mediaType: "tv")
    }

    func getTrendingTV(page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        return searchResults
    }

    func getSuggestionsTV(page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        return searchResults
    }

    func discoverMixed(genreID: Int, page: Int) async throws -> [Movie] {
        if let e = errorToThrow { throw e }
        return discoverResults
    }

    func fetchMovieCredits(id: Int) async throws -> Credits {
        if let e = errorToThrow { throw e }
        return Credits(cast: [], crew: [])
    }

    func fetchTVCredits(id: Int) async throws -> Credits {
        if let e = errorToThrow { throw e }
        return Credits(cast: [], crew: [])
    }

    func fetchTVDetail(id: Int) async throws -> TMDBTVDetailDTO {
        if let e = errorToThrow { throw e }
        return TMDBTVDetailDTO(id: id, name: nil, firstAirDate: nil, posterPath: nil, voteAverage: nil, overview: nil, episodeRunTime: nil, createdBy: nil)
    }
}
