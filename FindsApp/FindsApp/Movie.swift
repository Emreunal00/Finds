import Foundation

struct Movie: Identifiable, Equatable, Codable {
    let id: Int
    var title: String
    var year: Int
    var genres: [String]
    var posterName: String
    var rating: Double
    var summary: String
    var posterURL: URL?
    var durationMinutes: Int?
    
    var mediaType: String?
    var externalContentID: String?

    
    var cast: [String]?
    var directors: [String]?

    
    var popularity: Double?

    init(
        id: Int,
        title: String,
        year: Int,
        genres: [String] = [],
        posterName: String = "",
        rating: Double = 0.0,
        summary: String = "",
        posterURL: URL? = nil,
        durationMinutes: Int? = nil,
        mediaType: String? = nil,
        externalContentID: String? = nil,
        cast: [String]? = nil,
        directors: [String]? = nil,
        popularity: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.genres = genres
        self.posterName = posterName
        self.rating = rating
        self.summary = summary
        self.posterURL = posterURL
        self.durationMinutes = durationMinutes
        self.mediaType = mediaType
        self.externalContentID = externalContentID
        self.cast = cast
        self.directors = directors
        self.popularity = popularity
    }
}

extension Movie {
    var normalizedMediaType: String {
        (mediaType ?? "movie").lowercased()
    }

    var isBook: Bool {
        normalizedMediaType == "book"
    }
}

extension Profile {
    func shouldShowAsRecommendation(_ movie: Movie) -> Bool {
        !hasCompletedOrFavorited(movie)
    }

    private func hasCompletedOrFavorited(_ movie: Movie) -> Bool {
        if movie.isBook {
            return booksReadEntries.contains { matches($0, movie: movie, type: "book") }
                || watchedEntries.contains { matches($0, movie: movie, type: "book") }
                || favoritesEntries.contains { matches($0, movie: movie, type: "book") }
        }

        let type = movie.normalizedMediaType
        return watchedEntries.contains { matches($0, movie: movie, type: type) }
            || favoritesEntries.contains { matches($0, movie: movie, type: type) }
    }

    private func matches(_ entry: WatchedEntry, movie: Movie, type: String) -> Bool {
        guard entry.type.lowercased() == type else { return false }
        if entry.id == movie.id { return true }
        return movie.externalContentID != nil && entry.externalID == movie.externalContentID
    }
}
