import Foundation

// MARK: - TMDb API helper

struct TMDBAPI {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!
    static let apiKey: String = {
        return "b96a7f931a81af92f4742ecbdb4bef8d"
    }()

    static func posterURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return imageBaseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

// MARK: - TMDb DTOs

struct TMDBMovieResponse: Codable {
    let page: Int?
    let results: [TMDBMovie]
    let totalPages: Int?
    let totalResults: Int?
}

struct TMDBMovie: Codable {
    let id: Int
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?
    let genreIDs: [Int]?

    // NEW: popularity
    let popularity: Double?
}

struct TMDBMultiSearchResponse: Codable {
    let page: Int?
    let results: [TMDBMultiResult]
    let totalPages: Int?
    let totalResults: Int?
}

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

    // NEW: popularity
    let popularity: Double?
}

struct TMDBGenreList: Codable {
    let genres: [TMDBGenre]
}

struct TMDBGenre: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TMDBMovieDetail: Codable {
    let id: Int
    let runtime: Int?
}

struct TMDBTVDetail: Codable {
    let id: Int
    let episodeRunTime: [Int]?

    // NEW: Created by (for TV shows)
    let createdBy: [TMDBCreatedBy]?
}

struct TMDBCreatedBy: Codable {
    let id: Int?
    let creditId: String?
    let name: String?
    let gender: Int?
    let profilePath: String?
}

// Combined credits (already used elsewhere)
struct TMDBCombinedCredits: Codable {
    let id: Int
    let cast: [TMDBCombinedCast]
    let crew: [TMDBCombinedCrew]?
}

struct TMDBCombinedCast: Codable {
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
}

// NEW: Credits DTOs for movie/tv credits endpoints
struct TMDBCredits: Codable {
    let id: Int?
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Codable {
    let id: Int?
    let name: String?
    let character: String?
    let order: Int?
    let profilePath: String?
}

struct TMDBCrewMember: Codable {
    let id: Int?
    let name: String?
    let job: String?
    let department: String?
    let profilePath: String?
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
        let genreTokens: [String] = (genreIDs ?? []).map { "#\($0)" }

        return Movie(
            id: id,
            title: displayTitle,
            year: yearValue,
            genres: genreTokens,
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil,
            mediaType: "movie", // this struct represents movie endpoint items
            cast: nil,
            directors: nil,
            popularity: popularity
        )
    }
}

extension TMDBMultiResult {
    func toMovie() -> Movie? {
        guard let mt = mediaType, (mt == "movie" || mt == "tv") else { return nil }

        let displayTitle = title ?? name ?? "Untitled"
        let dateStr = (mt == "movie" ? releaseDate : firstAirDate) ?? releaseDate ?? firstAirDate ?? ""
        let yearValue: Int = {
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        let posterURL = TMDBAPI.posterURL(path: posterPath)
        let rating = (voteAverage ?? 0) / 2.0
        let genreTokens: [String] = (genreIDs ?? []).map { "#\($0)" }

        return Movie(
            id: id,
            title: displayTitle,
            year: yearValue,
            genres: genreTokens,
            posterName: "",
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL,
            durationMinutes: nil,
            mediaType: mt,
            cast: nil,
            directors: nil,
            popularity: popularity
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
            durationMinutes: nil,
            mediaType: mt,
            cast: nil,
            directors: nil,
            popularity: nil
        )
    }
}

