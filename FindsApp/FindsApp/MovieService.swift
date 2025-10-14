// MovieService.swift
import Foundation

protocol MovieServicing {
    func getTrending(page: Int) async throws -> [Movie]
    func getSuggestions(page: Int) async throws -> [Movie]
    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int) async throws -> [Movie]
    func fetchGenres() async throws -> [TMDBGenre]
}

final class MovieService: MovieServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getTrending(page: Int = 1) async throws -> [Movie] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("trending/movie/week"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "page", value: String(page))
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        return resp.results.map { $0.toMovie() }
    }

    func getSuggestions(page: Int = 1) async throws -> [Movie] {
        // Discover: popüler ve puanı belirli eşiğin üstünde filmler
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("discover/movie"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "vote_average.gte", value: "6.5"),
            .init(name: "page", value: String(page))
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        return resp.results.map { $0.toMovie() }
    }

    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int = 1) async throws -> [Movie] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("search/movie"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "query", value: query),
            .init(name: "include_adult", value: "false"),
            .init(name: "page", value: String(page))
        ]
        if let year { items.append(.init(name: "year", value: String(year))) }
        // TMDb search endpoint genre filtrelemeyi doğrudan desteklemiyor; discover ile filtrelenebilir.
        comps.queryItems = items

        let (data, _) = try await session.data(from: try comps.asURL())
        let resp = try JSONDecoder().decode(TMDBMovieResponse.self, from: data)
        var movies = resp.results
        if let genreID {
            movies = movies.filter { $0.genreIDs?.contains(genreID) == true }
        }
        return movies.map { $0.toMovie() }
    }

    func fetchGenres() async throws -> [TMDBGenre] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("genre/movie/list"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let (data, _) = try await session.data(from: try comps.asURL())
        let list = try JSONDecoder().decode(TMDBGenreList.self, from: data)
        return list.genres
    }
}

private extension URLComponents {
    func asURL() throws -> URL {
        guard let url = url else { throw URLError(.badURL) }
        return url
    }
}

private extension TMDBMovie {
    func toMovie() -> Movie {
        // title fallback: bazı kayıtlarda name alanı kullanılabiliyor (TV vs.)
        let displayTitle = title ?? name ?? "Untitled"
        // year: releaseDate "YYYY-MM-DD" formatından yıl çıkar
        let yearValue: Int = {
            let dateStr = releaseDate ?? firstAirDate ?? ""
            if let y = dateStr.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        let posterURL = TMDBAPI.posterURL(path: posterPath)
        let rating = (voteAverage ?? 0) / 2.0 // TMDb 0...10, biz 0...5 gösteriyoruz
        // Genres: ID'lerden isim çözmek için genre listesi gerekir; şimdilik ID stringleri
        let genreStrings = (genreIDs ?? []).map { "#\($0)" }

        return Movie(
            title: displayTitle,
            year: yearValue,
            genres: genreStrings,
            posterName: "", // artık kullanılmayacak, ContentView’de posterURL kullanacağız
            rating: rating,
            summary: overview ?? "",
            posterURL: posterURL
        )
    }
}
