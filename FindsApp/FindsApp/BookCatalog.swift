import Foundation

enum BookCatalog {
    static let popularShelf: [Movie] = [
        makeBook(id: 900001, title: "Fourth Wing", year: 2023, genres: ["Fantasy", "Romance"], rating: 4.4, summary: "A dragon rider fantasy about survival, rivalry, and dangerous alliances at Basgiath War College.", author: "Rebecca Yarros"),
        makeBook(id: 900002, title: "Iron Flame", year: 2023, genres: ["Fantasy", "Adventure"], rating: 4.3, summary: "Violet returns to a deadlier stage of training where secrets, power, and trust collide.", author: "Rebecca Yarros"),
        makeBook(id: 900003, title: "The Housemaid", year: 2022, genres: ["Thriller", "Mystery"], rating: 4.1, summary: "A domestic thriller about a live-in housemaid who slowly realizes the family she works for is not what it seems.", author: "Freida McFadden"),
        makeBook(id: 900004, title: "Tomorrow, and Tomorrow, and Tomorrow", year: 2022, genres: ["Drama", "Literary Fiction"], rating: 4.2, summary: "Two game designers build worlds together while navigating ambition, grief, and friendship.", author: "Gabrielle Zevin"),
        makeBook(id: 900005, title: "The Women", year: 2024, genres: ["Historical Fiction"], rating: 4.5, summary: "A Vietnam War-era story focused on service, sacrifice, and the women often erased from history.", author: "Kristin Hannah"),
        makeBook(id: 900006, title: "Yellowface", year: 2023, genres: ["Satire", "Thriller"], rating: 4.0, summary: "A sharp publishing satire about envy, theft, identity, and literary fame.", author: "R. F. Kuang")
    ]

    static let recommendedShelf: [Movie] = [
        makeBook(id: 900007, title: "Project Hail Mary", year: 2021, genres: ["Science Fiction"], rating: 4.6, summary: "A lone astronaut wakes up on a mission to save Earth with no memory and one unlikely ally.", author: "Andy Weir"),
        makeBook(id: 900008, title: "Remarkably Bright Creatures", year: 2022, genres: ["Contemporary", "Feel-Good"], rating: 4.3, summary: "An offbeat, tender mystery connecting an elderly woman, a lost young man, and a clever octopus.", author: "Shelby Van Pelt"),
        makeBook(id: 900009, title: "Divine Rivals", year: 2023, genres: ["Fantasy", "Romance"], rating: 4.2, summary: "Two rival journalists exchange anonymous letters during a war touched by gods.", author: "Rebecca Ross"),
        makeBook(id: 900010, title: "Demon Copperhead", year: 2022, genres: ["Drama", "Literary Fiction"], rating: 4.4, summary: "A modern Appalachian coming-of-age story about resilience, poverty, and survival.", author: "Barbara Kingsolver"),
        makeBook(id: 900011, title: "The Midnight Library", year: 2020, genres: ["Fantasy", "Drama"], rating: 4.0, summary: "A woman explores alternate versions of her life in a library between life and death.", author: "Matt Haig"),
        makeBook(id: 900012, title: "The Silent Patient", year: 2019, genres: ["Thriller", "Psychological"], rating: 4.1, summary: "A therapist becomes obsessed with uncovering why a famous artist shot her husband and then stopped speaking.", author: "Alex Michaelides")
    ]

    static var allBooks: [Movie] {
        popularShelf + recommendedShelf.filter { candidate in
            !popularShelf.contains(where: { $0.id == candidate.id })
        }
    }

    static func trendingBooks() async -> [Movie] {
        popularShelf
    }

    static func recommendedBooks(for userID: String?) async -> [Movie] {
        recommendedShelf
    }

    static func fetchBook(id: Int) throws -> Movie {
        guard let book = allBooks.first(where: { $0.id == id }) else {
            throw NSError(domain: "BookCatalog", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Book not found."
            ])
        }
        return book
    }

    static func fetchMedia(id: Int, type: String, service: MovieServicing = MovieService()) async throws -> Movie {
        switch type.lowercased() {
        case "book":
            return try fetchBook(id: id)
        case "tv":
            return try await service.fetchTVBasic(id: id)
        default:
            return try await service.fetchMovieBasic(id: id)
        }
    }

    static func symbolName(for movie: Movie) -> String {
        movie.isBook ? "book.closed" : "film"
    }

    private static func makeBook(
        id: Int,
        title: String,
        year: Int,
        genres: [String],
        rating: Double,
        summary: String,
        author: String
    ) -> Movie {
        Movie(
            id: id,
            title: title,
            year: year,
            genres: genres,
            posterName: "",
            rating: rating,
            summary: summary,
            posterURL: nil,
            durationMinutes: nil,
            mediaType: "book",
            cast: nil,
            directors: [author],
            popularity: rating * 10
        )
    }
}
