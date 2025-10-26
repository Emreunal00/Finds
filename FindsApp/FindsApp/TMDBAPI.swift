import Foundation

// MARK: - TMDb API helper

struct TMDBAPI {
    // Base API URL
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!

    // Base image URL (w500 is a good default size for posters)
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!

    // Provide your TMDb API key here, or load from Info.plist if you prefer
    static let apiKey: String = {
        // If you want to load from Info.plist, uncomment below and add a key "TMDB_API_KEY"
        // return Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
        return "b96a7f931a81af92f4742ecbdb4bef8d"
    }()

    // Helper to build full poster URL from a poster path like "/abc123.jpg"
    static func posterURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return imageBaseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

// MARK: - TMDb DTOs

// List response for endpoints like trending/movie, discover/movie, search/movie
struct TMDBMovieResponse: Codable {
    let page: Int?
    let results: [TMDBMovie]
    let totalPages: Int?
    let totalResults: Int?
}

// Basic movie item used in list endpoints
struct TMDBMovie: Codable {
    let id: Int
    let title: String?
    let name: String?           // sometimes present in TV contexts; kept for safety
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?
    let genreIDs: [Int]?
}

// Multi-search response
struct TMDBMultiSearchResponse: Codable {
    let page: Int?
    let results: [TMDBMultiResult]
    let totalPages: Int?
    let totalResults: Int?
}

// Item for multi-search; can be movie or tv (we only map those)
struct TMDBMultiResult: Codable {
    let mediaType: String?      // "movie", "tv", "person", ...
    let id: Int
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?
    let genreIDs: [Int]?
}

// Genres
struct TMDBGenreList: Codable {
    let genres: [TMDBGenre]
}

struct TMDBGenre: Codable, Identifiable {
    let id: Int
    let name: String
}

// Details for movie
struct TMDBMovieDetail: Codable {
    let id: Int
    let runtime: Int?
}

// Details for TV
struct TMDBTVDetail: Codable {
    let id: Int
    let episodeRunTime: [Int]?
}

// MARK: - Combined Credits (person/{id}/combined_credits)

struct TMDBCombinedCredits: Codable {
    let id: Int
    let cast: [TMDBCombinedCast]
    let crew: [TMDBCombinedCrew]?
}

struct TMDBCombinedCast: Codable {
    let id: Int
    let mediaType: String?      // "movie" or "tv"
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?
    let genreIDs: [Int]?
    // role fields omitted for brevity (character, credit_id, etc.)
}

struct TMDBCombinedCrew: Codable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?
    let genreIDs: [Int]?
    // job fields omitted for brevity
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

        // Use "#<id>" tokens for genre filtering
        let genreTokens: [String] = (genreIDs ?? []).map { "#\($0)" }

        return Movie(
            id: id, // TMDB id
            title: displayTitle,
            year: yearValue,
            genres: genreTokens,
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil
        )
    }
}

extension TMDBMultiResult {
    func toMovie() -> Movie? {
        guard let mt = mediaType, (mt == "movie" || mt == "tv") else { return nil }

        let displayTitle = title ?? name ?? "Untitled"
        let yearValue: Int = {
            let dateStr = (mt == "movie" ? releaseDate : firstAirDate) ?? releaseDate ?? firstAirDate ?? ""
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        let posterURL = TMDBAPI.posterURL(path: posterPath)
        let rating = (voteAverage ?? 0) / 2.0

        let genreTokens: [String] = (genreIDs ?? []).map { "#\($0)" }

        return Movie(
            id: id, // TMDB id
            title: displayTitle,
            year: yearValue,
            genres: genreTokens,
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil
        )
    }
}

extension TMDBCombinedCast {
    func toMovieIfSupported() -> Movie? {
        guard let mt = mediaType, (mt == "movie" || mt == "tv") else { return nil }
        let displayTitle = title ?? name ?? "Untitled"
        let dateStr = (mt == "movie" ? releaseDate : firstAirDate) ?? releaseDate ?? firstAirDate ?? ""
        let yearValue: Int = {
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        return Movie(
            id: id,
            title: displayTitle,
            year: yearValue,
            genres: (genreIDs ?? []).map { "#\($0)" },
            posterName: "",
            rating: (voteAverage ?? 0) / 2.0,
            summary: overview ?? "",
            posterURL: TMDBAPI.posterURL(path: posterPath),
            durationMinutes: nil
        )
    }
}

