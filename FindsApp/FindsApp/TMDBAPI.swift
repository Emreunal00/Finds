// TMDBAPI.swift
import Foundation

enum TMDBAPI {
    static let apiKey = "YOUR_TMDB_API_KEY"
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/")!
    static let posterSize = "w342" // alternatif: w185, w500

    static func posterURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return imageBaseURL.appendingPathComponent(posterSize).appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

// MARK: - TMDb Models

struct TMDBMovieResponse: Decodable {
    let page: Int
    let results: [TMDBMovie]
    let totalPages: Int?
    let totalResults: Int?

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDBMovie: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIDs: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }
}

// Opsiyonel: Genre endpoint’inden isimleri çekmek istersek
struct TMDBGenreList: Decodable {
    let genres: [TMDBGenre]
}
struct TMDBGenre: Decodable, Hashable {
    let id: Int
    let name: String
}
