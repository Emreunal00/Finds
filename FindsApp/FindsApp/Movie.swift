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

    init(
        id: Int,
        title: String,
        year: Int,
        genres: [String] = [],
        posterName: String = "",
        rating: Double = 0.0,
        summary: String = "",
        posterURL: URL? = nil,
        durationMinutes: Int? = nil
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
    }
}
