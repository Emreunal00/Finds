// MovieService.swift
import Foundation

protocol MovieServicing {
    func getTrending(page: Int) async throws -> [Movie]
    func getSuggestions(page: Int) async throws -> [Movie]
    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int) async throws -> [Movie]
    func fetchGenres() async throws -> [TMDBGenre]
    func searchMulti(query: String, page: Int) async throws -> [Movie]
    func fetchMovieRuntime(id: Int) async throws -> Int?
    func fetchTVRuntime(id: Int) async throws -> Int?
    func fetchMovieBasic(id: Int) async throws -> Movie
    func fetchTVBasic(id: Int) async throws -> Movie
}

final class MovieService: MovieServicing {
    private let maxRuntimeEnrichmentCount = 6
    private let runtimeConcurrencyLimit = 2

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 20
            cfg.timeoutIntervalForResource = 30
            cfg.waitsForConnectivity = true
            cfg.requestCachePolicy = .useProtocolCachePolicy
            self.session = URLSession(configuration: cfg)
        }

        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = d
    }

    func getTrending(page: Int = 1) async throws -> [Movie] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("trending/movie/week"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "page", value: String(page))
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "trending/movie/week", maxRetries: 3, initialDelay: 0.8)
        let resp = try decode(TMDBMovieResponse.self, from: data, endpoint: "trending/movie/week")
        var movies = resp.results.map { $0.toMovie() }
        movies = try await enrichMoviesWithRuntime(fromMovies: resp.results, baseMovies: movies)
        return movies
    }

    func getSuggestions(page: Int = 1) async throws -> [Movie] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("discover/movie"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "vote_average.gte", value: "6.5"),
            .init(name: "page", value: String(page))
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "discover/movie", maxRetries: 3, initialDelay: 0.8)
        let resp = try decode(TMDBMovieResponse.self, from: data, endpoint: "discover/movie")
        var movies = resp.results.map { $0.toMovie() }
        movies = try await enrichMoviesWithRuntime(fromMovies: resp.results, baseMovies: movies)
        return movies
    }

    func searchMovies(query: String, year: Int?, genreID: Int?, page: Int = 1) async throws -> [Movie] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("search/movie"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "query", value: query),
            .init(name: "include_adult", value: "false"),
            .init(name: "page", value: String(page))
        ]
        if let year { items.append(.init(name: "year", value: String(year))) }
        comps.queryItems = items

        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "search/movie", maxRetries: 3, initialDelay: 0.8)
        let resp = try decode(TMDBMovieResponse.self, from: data, endpoint: "search/movie")

        var tmdbMovies = resp.results
        if let genreID {
            tmdbMovies = tmdbMovies.filter { $0.genreIDs?.contains(genreID) == true }
        }
        let movies = tmdbMovies.map { $0.toMovie() }
        return movies
    }

    func searchMulti(query: String, page: Int = 1) async throws -> [Movie] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        do {
            var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("search/multi"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "api_key", value: TMDBAPI.apiKey),
                .init(name: "language", value: "en-US"),
                .init(name: "query", value: trimmed),
                .init(name: "include_adult", value: "false"),
                .init(name: "page", value: String(page))
            ]

            let url = try comps.asURL()
            let data = try await requestData(url: url, context: "search/multi", maxRetries: 3, initialDelay: 0.8)
            let resp = try decode(TMDBMultiSearchResponse.self, from: data, endpoint: "search/multi")

            var mapped: [Movie] = resp.results.compactMap { $0.toMovie() }

            if let bestPerson = resp.results.first(where: { ($0.mediaType ?? "") == "person" }) {
                let personMovies = try await fetchCombinedCredits(personId: bestPerson.id)
                let existingIDs = Set(mapped.map { $0.id })
                let uniqueFromPerson = personMovies.filter { !existingIDs.contains($0.id) }
                mapped.append(contentsOf: uniqueFromPerson)
            }
            return mapped
        } catch {
            print("[TMDB] search/multi failed, falling back to search/movie. Error:", error)
            return try await searchMovies(query: trimmed, year: nil, genreID: nil, page: page)
        }
    }

    func fetchGenres() async throws -> [TMDBGenre] {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("genre/movie/list"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "genre/movie/list", maxRetries: 3, initialDelay: 0.8)
        let list = try decode(TMDBGenreList.self, from: data, endpoint: "genre/movie/list")
        return list.genres
    }

    func fetchMovieRuntime(id: Int) async throws -> Int? {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("movie/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "movie/\(id)", maxRetries: 3, initialDelay: 0.8)
        let detail = try decode(TMDBMovieDetail.self, from: data, endpoint: "movie/\(id)")
        return detail.runtime
    }

    func fetchTVRuntime(id: Int) async throws -> Int? {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("tv/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "tv/\(id)", maxRetries: 3, initialDelay: 0.8)
        let detail = try decode(TMDBTVDetail.self, from: data, endpoint: "tv/\(id)")
        return detail.episodeRunTime?.first
    }

    func fetchMovieBasic(id: Int) async throws -> Movie {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("movie/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "movie/\(id)", maxRetries: 3, initialDelay: 0.8)
        let detail = try decode(TMDBMovieSummary.self, from: data, endpoint: "movie/\(id)")
        var m = detail.toMovie()
        m.mediaType = "movie"
        return m
    }

    func fetchTVBasic(id: Int) async throws -> Movie {
        var comps = URLComponents(url: TMDBAPI.baseURL.appendingPathComponent("tv/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: TMDBAPI.apiKey),
            .init(name: "language", value: "en-US")
        ]
        let url = try comps.asURL()
        let data = try await requestData(url: url, context: "tv/\(id)", maxRetries: 3, initialDelay: 0.8)
        let detail = try decode(TMDBTVSummary.self, from: data, endpoint: "tv/\(id)")
        var m = detail.toMovie()
        m.mediaType = "tv"
        return m
    }

    private func enrichMoviesWithRuntime(fromMovies tmdb: [TMDBMovie], baseMovies: [Movie]) async throws -> [Movie] {
        let slice = Array(tmdb.prefix(maxRuntimeEnrichmentCount))
        let ids = slice.map { $0.id }
        let runtimeMap = try await fetchRuntimesLimited(ids: ids, isTV: false)
        var result = baseMovies
        for (idx, tm) in slice.enumerated() {
            if idx < result.count {
                result[idx].durationMinutes = runtimeMap[tm.id] ?? nil
            }
        }
        return result
    }

    private func fetchRuntimesLimited(ids: [Int], isTV: Bool) async throws -> [Int: Int?] {
        var result: [Int: Int?] = [:]
        if ids.isEmpty { return result }

        var pending = Array(ids)
        var active: [Task<(Int, Int?), Error>] = []

        func launchNext() {
            guard !pending.isEmpty else { return }
            let id = pending.removeFirst()
            let task = Task { () -> (Int, Int?) in
                if isTV {
                    let rt = try await self.fetchTVRuntime(id: id)
                    return (id, rt)
                } else {
                    let rt = try await self.fetchMovieRuntime(id: id)
                    return (id, rt)
                }
            }
            active.append(task)
        }

        for _ in 0..<min(runtimeConcurrencyLimit, pending.count) {
            launchNext()
        }

        while !active.isEmpty {
            let finished = try await withThrowingTaskGroup(of: (Int, Int?).self) { group -> (Int, Int?) in
                for t in active {
                    group.addTask { try await t.value }
                }
                let value = try await group.next()!
                group.cancelAll()
                return value
            }

            result[finished.0] = finished.1
            active.forEach { $0.cancel() }
            active.removeAll()
            launchNext()
        }

        return result
    }

    private func requestData(url: URL, context: String, maxRetries: Int = 3, initialDelay: TimeInterval = 0.8) async throws -> Data {
        var attempt = 0
        var delay = initialDelay

        while true {
            do {
                let (data, response) = try await session.data(from: url)
                try throwIfHTTPError(data: data, response: response, context: context)
                return data
            } catch {
                attempt += 1
                if shouldRetry(error: error), attempt <= maxRetries {
                    print("[TMDB] \(context) attempt \(attempt) failed, retrying in \(String(format: "%.2f", delay))s. Error:", error)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                    continue
                } else {
                    throw error
                }
            }
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let retryable: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed
            ]
            return retryable.contains(ns.code)
        }
        if ns.domain == "TMDBHTTP" {
            return (500...599).contains(ns.code) || ns.code == 429
        }
        return false
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let sample = String(decoding: data.prefix(512), as: UTF8.self)
            print("[TMDB] Decode error at \(endpoint):", error)
            print("[TMDB] Payload sample:", sample)
            throw error
        }
    }

    private func throwIfHTTPError(data: Data, response: URLResponse, context: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            let err = NSError(
                domain: "TMDBHTTP",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "TMDb \(context) failed with status \(http.statusCode)",
                    "body": body
                ]
            )
            print("[TMDB] HTTP error \(http.statusCode) at \(context). Body:", body)
            throw err
        }
    }
}

private extension URLComponents {
    func asURL() throws -> URL {
        guard let url = url else { throw URLError(.badURL) }
        return url
    }
}

struct TMDBMovieSummary: Codable {
    let id: Int
    let title: String?
    let releaseDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?

    func toMovie() -> Movie {
        let yearValue: Int = {
            if let d = releaseDate, let y = d.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        return Movie(
            id: id,
            title: title ?? "Untitled",
            year: yearValue,
            genres: [],
            posterName: "",
            rating: (voteAverage ?? 0) / 2.0,
            summary: overview ?? "",
            posterURL: TMDBAPI.posterURL(path: posterPath),
            durationMinutes: nil,
            mediaType: "movie"
        )
    }
}

struct TMDBTVSummary: Codable {
    let id: Int
    let name: String?
    let firstAirDate: String?
    let posterPath: String?
    let voteAverage: Double?
    let overview: String?

    func toMovie() -> Movie {
        let yearValue: Int = {
            if let d = firstAirDate, let y = d.split(separator: "-").first, let yi = Int(y) { return yi }
            return 0
        }()
        return Movie(
            id: id,
            title: name ?? "Untitled",
            year: yearValue,
            genres: [],
            posterName: "",
            rating: (voteAverage ?? 0) / 2.0,
            summary: overview ?? "",
            posterURL: TMDBAPI.posterURL(path: posterPath),
            durationMinutes: nil,
            mediaType: "tv"
        )
    }
}

