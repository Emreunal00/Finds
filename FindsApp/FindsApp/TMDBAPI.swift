// TMDBAPI.swift
import Foundation

enum TMDBAPI {
    static let apiKey = "b96a7f931a81af92f4742ecbdb4bef8d"
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

// MARK: - Multi Search Models

struct TMDBMultiSearchResponse: Decodable {
    let page: Int
    let results: [TMDBMultiResult]
    let totalPages: Int?
    let totalResults: Int?

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDBMultiResult: Decodable {
    let id: Int
    let mediaType: String // "movie" | "tv" | "person"
    // ortak alanlar
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIDs: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title, name, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }
}

// MARK: - Detail Models

struct TMDBMovieDetail: Decodable {
    let id: Int
    let runtime: Int? // minutes
}

struct TMDBTVDetail: Decodable {
    let id: Int
    let episodeRunTime: [Int]? // minutes, array
    private enum CodingKeys: String, CodingKey {
        case id
        case episodeRunTime = "episode_run_time"
    }
}

// MARK: - Mapping to app model

extension TMDBMovie {
    func toMovie() -> Movie {
        let displayTitle = title ?? name ?? "Untitled"
        let yearValue: Int = {
            let dateStr = releaseDate ?? firstAirDate ?? ""
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        let posterURL = TMDBAPI.posterURL(path: posterPath)
        let rating = (voteAverage ?? 0) / 2.0
        // Genres yerine artık süre kullanacağız; süre detay isteği ile doldurulacak.
        return Movie(
            title: displayTitle,
            year: yearValue,
            genres: [], // artık “#id” yok
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil // detaydan doldurulacak
        )
    }
}

extension TMDBMultiResult {
    func toMovie() -> Movie? {
        guard mediaType == "movie" || mediaType == "tv" else { return nil }
        let displayTitle = title ?? name ?? "Untitled"
        let yearValue: Int = {
            let dateStr = (mediaType == "movie" ? releaseDate : firstAirDate) ?? releaseDate ?? firstAirDate ?? ""
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        let posterURL = TMDBAPI.posterURL(path: posterPath)
        let rating = (voteAverage ?? 0) / 2.0

        return Movie(
            title: displayTitle,
            year: yearValue,
            genres: [], // artık “#id” yok
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil // detaydan doldurulacak
        )
    }
}
