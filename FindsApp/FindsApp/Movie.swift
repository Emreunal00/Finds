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
    // NEW: mediaType ("movie" or "tv")
    var mediaType: String?
    var externalContentID: String?

    // NEW: Credits fields
    var cast: [String]?
    var directors: [String]?

    // NEW: Popularity (for sorting search results)
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
