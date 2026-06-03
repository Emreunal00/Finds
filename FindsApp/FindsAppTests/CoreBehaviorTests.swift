import Foundation
import Testing
@testable import FindsApp

@Suite("Core Model Behavior")
@MainActor
struct CoreModelBehaviorTests {
    @Test("Movie defaults to movie media type")
    func movieDefaultsToMovieMediaType() {
        let movie = Movie(id: 1, title: "Arrival", year: 2016)

        #expect(movie.normalizedMediaType == "movie")
        #expect(movie.isBook == false)
    }

    @Test("Book media type is case insensitive")
    func bookMediaTypeIsCaseInsensitive() {
        let book = Movie(id: 2, title: "Dune", year: 1965, mediaType: "BOOK", externalContentID: "external-book-id")

        #expect(book.normalizedMediaType == "book")
        #expect(book.isBook)
        #expect(book.externalContentID == "external-book-id")
    }

    @Test("Profile keeps screen and book lists separate")
    func profileKeepsScreenAndBookListsSeparate() {
        let watched = WatchedEntry(id: 10, type: "movie")
        let watchlist = WatchedEntry(id: 11, type: "tv")
        let read = WatchedEntry(id: 12, type: "book", externalID: "read-book")
        let wantToRead = WatchedEntry(id: 13, type: "book", externalID: "want-book")

        let profile = Profile(
            id: "profile-1",
            displayName: "Reader",
            watchedEntries: [watched],
            watchlistEntries: [watchlist],
            booksReadEntries: [read],
            booksWantToReadEntries: [wantToRead]
        )

        #expect(profile.watchedEntries == [watched])
        #expect(profile.watchlistEntries == [watchlist])
        #expect(profile.booksReadEntries == [read])
        #expect(profile.booksWantToReadEntries == [wantToRead])
    }

    @Test("Recommendations hide only current profile completed and favorite items")
    func recommendationsHideOnlyCurrentProfileCompletedAndFavoriteItems() {
        let currentProfile = Profile(
            id: "profile-1",
            watchedEntries: [WatchedEntry(id: 10, type: "movie")],
            favoritesEntries: [WatchedEntry(id: 20, type: "tv")],
            booksReadEntries: [WatchedEntry(id: 30, type: "book", externalID: "book-30")]
        )
        let otherProfile = Profile(
            id: "profile-2",
            watchedEntries: [WatchedEntry(id: 40, type: "movie")]
        )

        let watchedMovie = Movie(id: 10, title: "Watched", year: 2020, mediaType: "movie")
        let favoriteShow = Movie(id: 20, title: "Favorite", year: 2020, mediaType: "tv")
        let readBook = Movie(id: 999, title: "Read", year: 2020, mediaType: "book", externalContentID: "book-30")
        let otherProfileMovie = Movie(id: 40, title: "Other", year: 2020, mediaType: "movie")

        #expect(currentProfile.shouldShowAsRecommendation(watchedMovie) == false)
        #expect(currentProfile.shouldShowAsRecommendation(favoriteShow) == false)
        #expect(currentProfile.shouldShowAsRecommendation(readBook) == false)
        #expect(currentProfile.shouldShowAsRecommendation(otherProfileMovie))
        #expect(otherProfile.shouldShowAsRecommendation(watchedMovie))
    }

    @Test("BookCatalog symbol matches content type")
    func bookCatalogSymbolMatchesContentType() {
        let book = Movie(id: 1, title: "Book", year: 2020, mediaType: "book")
        let movie = Movie(id: 2, title: "Movie", year: 2020, mediaType: "movie")

        #expect(BookCatalog.symbolName(for: book) == "book.closed")
        #expect(BookCatalog.symbolName(for: movie) == "film")
    }
}

@Suite("Mock Service Behavior")
@MainActor
struct MockServiceBehaviorTests {
    @Test("SearchMovies filters by year and genre")
    func searchMoviesFiltersByYearAndGenre() async throws {
        var service = MockMovieService()
        service.searchResults = [
            Movie(id: 1, title: "Action 2020", year: 2020, genres: ["#28"], mediaType: "movie"),
            Movie(id: 2, title: "Action 2021", year: 2021, genres: ["#28"], mediaType: "movie"),
            Movie(id: 3, title: "Drama 2020", year: 2020, genres: ["#18"], mediaType: "movie")
        ]

        let results = try await service.searchMovies(query: "action", year: 2020, genreID: 28, page: 1)

        #expect(results.map(\.id) == [1])
    }

    @Test("SearchMovies returns empty results for blank query")
    func searchMoviesReturnsEmptyForBlankQuery() async throws {
        var service = MockMovieService()
        service.searchResults = [Movie(id: 1, title: "Any", year: 2020)]

        let results = try await service.searchMovies(query: "   ", year: nil, genreID: nil, page: 1)

        #expect(results.isEmpty)
    }

    @Test("FetchMedia routes screen content through injected service")
    func fetchMediaRoutesScreenContentThroughInjectedService() async throws {
        let service = MockMovieService()

        let movie = try await BookCatalog.fetchMedia(id: 44, type: "movie", service: service)
        let tv = try await BookCatalog.fetchMedia(id: 55, type: "tv", service: service)

        #expect(movie.title == "Movie #44")
        #expect(movie.mediaType == "movie")
        #expect(tv.title == "TV #55")
        #expect(tv.mediaType == "tv")
    }
}

@Suite("Ratings Store Behavior")
struct RatingsStoreBehaviorTests {
    @Test("User ratings are stored and removed by media type")
    func userRatingsAreStoredAndRemovedByMediaType() {
        let userID = "test-user-ratings-store"
        let movieID = 987_001

        RatingsStore.removeRating(for: userID, movieID: movieID, type: "movie")
        RatingsStore.setRating(4.5, for: userID, movieID: movieID, type: "movie")

        #expect(RatingsStore.rating(for: userID, movieID: movieID, type: "movie") == 4.5)
        #expect(RatingsStore.rating(for: userID, movieID: movieID, type: "book") == nil)

        RatingsStore.removeRating(for: userID, movieID: movieID, type: "movie")
        #expect(RatingsStore.rating(for: userID, movieID: movieID, type: "movie") == nil)
    }

    @Test("Aggregate average updates with deltas")
    func aggregateAverageUpdatesWithDeltas() {
        let movieID = 987_002

        RatingsStore.setAggregate(total: 0, count: 0, for: movieID, type: "movie")
        let first = RatingsStore.applyDelta(for: movieID, type: "movie", add: 4, incrementCount: true)
        let second = RatingsStore.applyDelta(for: movieID, type: "movie", add: 2, incrementCount: true)
        let adjusted = RatingsStore.applyDelta(for: movieID, type: "movie", add: -1, incrementCount: false)

        #expect(first.total == 4)
        #expect(first.count == 1)
        #expect(second.average == 3)
        #expect(adjusted.total == 5)
        #expect(adjusted.count == 2)
        #expect(adjusted.average == 2.5)
    }
}
